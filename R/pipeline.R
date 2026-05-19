# =============================================================================
# pipeline.R — orquestrador da coleta para um projeto
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(tibble)
})

# Carrega todas as fontes (uso interativo / via cli.R)
folha_load_all <- function() {
  src_dir <- file.path(getwd(), "R")
  for (f in c("db.R", "utils.R", "scrape.R", "dedup.R", "projects.R", "llm.R")) {
    sys.source(file.path(src_dir, f), envir = globalenv())
  }
  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# Processa UMA keyword do projeto.
# Retorna lista com contagens.
# -----------------------------------------------------------------------------
process_keyword <- function(con, project, keyword_row, skip_llm = FALSE,
                              n_few_shot = 8, api_key = NULL) {
  kw    <- keyword_row$keyword
  kw_id <- keyword_row$id

  log_section(paste0("KEYWORD: ", kw))
  project_keyword_mark(con, kw_id, "searching")

  dates <- keyword_effective_dates(con, project$id, kw_id)

  # --- Fase 1: busca ---
  results <- tryCatch(
    search_keyword(kw, dates$start, dates$end),
    error = function(e) {
      project_keyword_mark(con, kw_id, "failed", error_msg = conditionMessage(e))
      stop(e)
    }
  )

  if (nrow(results) == 0) {
    log_msg("Nenhum resultado para '", kw, "'")
    project_keyword_mark(con, kw_id, "done",
                         n_search_raw = 0, n_new_added = 0, n_existing_matched = 0)
    return(list(raw = 0, new = 0, matched = 0))
  }

  log_msg("Total bruto: ", nrow(results))

  # --- Fase 2: dedup interno (mesmo URL, múltiplas linhas) ---
  results <- dedup_internal(results)

  # --- Fase 3: separa entre artigos já no banco × novos ---
  existing_urls <- dbGetQuery(con,
    "SELECT url_clean FROM articles WHERE url_clean IN ("
    |> paste0(paste(rep("?", nrow(results)), collapse = ","), ")"),
    params = as.list(results$url_clean)
  )$url_clean

  already_in_db   <- results |> filter(url_clean %in% existing_urls)
  candidates_new  <- results |> filter(!url_clean %in% existing_urls)

  log_msg("  ", nrow(already_in_db), " já no banco | ",
          nrow(candidates_new), " URLs novas")

  # --- Fase 4: fuzzy dedup contra títulos do BANCO INTEIRO ---
  if (nrow(candidates_new) > 0) {
    all_title_norms <- dbGetQuery(con,
      "SELECT title_norm FROM articles WHERE title_norm IS NOT NULL")$title_norm
    fz <- dedup_fuzzy(candidates_new, all_title_norms)
    candidates_new <- fz$new_clean
    if (nrow(fz$fuzzy_dups) > 0) {
      log_msg("  Fuzzy removidos: ", nrow(fz$fuzzy_dups))
    }
  }

  # --- Fase 5: insere artigos novos + linka todos os artigos ao projeto ---
  n_new <- 0
  for (i in seq_len(nrow(candidates_new))) {
    row <- candidates_new[i, ]
    inserted <- db_upsert_article(con, list(
      url_clean       = row$url_clean,
      url             = row$url,
      title           = row$title,
      title_norm      = row$title_norm,
      date            = row$date,
      date_raw        = row$date_raw,
      section         = row$section,
      excerpt         = row$excerpt,
      era             = row$era,
      fulltext_status = "pending"
    ))
    if (inserted) n_new <- n_new + 1
    db_link_article_to_project(con, project$id, row$url_clean, kw)
  }
  for (i in seq_len(nrow(already_in_db))) {
    db_link_article_to_project(con, project$id, already_in_db$url_clean[i], kw)
  }

  # --- Fase 6: coleta de fulltext (apenas para os 'pending') ---
  to_fetch <- dbGetQuery(con,
    "SELECT a.url_clean FROM articles a
     JOIN project_articles pa ON pa.url_clean = a.url_clean
     WHERE pa.project_id = ?
       AND a.fulltext_status = 'pending'
       AND (a.url_clean IN ("
    |> paste0(paste(rep("?", nrow(results)), collapse = ","), "))"),
    params = c(list(project$id), as.list(results$url_clean))
  )$url_clean

  log_msg("Fulltext a coletar: ", length(to_fetch))
  for (i in seq_along(to_fetch)) {
    u <- to_fetch[i]
    log_msg("  [", i, "/", length(to_fetch), "] ", substr(u, 1, 65))
    ft <- fetch_fulltext(u)
    db_update_fulltext(con, u, ft$full_text, status = ft$status)
  }

  # --- Fase 7: classificação LLM (opcional) ---
  if (!skip_llm) {
    log_msg("Classificando via LLM (modo: ",
            if (n_few_shot > 0) "few-shot" else "zero-shot", ")")
    if (is.null(api_key)) api_key <- get_api_key()
    examples <- load_few_shot(con, project$id, n_few_shot)

    to_classify <- dbGetQuery(con,
      "SELECT a.url_clean, a.title, a.excerpt, a.full_text,
              pa.matched_keywords
       FROM articles a
       JOIN project_articles pa ON pa.url_clean = a.url_clean
       LEFT JOIN classifications c ON c.url_clean = a.url_clean AND c.project_id = pa.project_id
       WHERE pa.project_id = ?
         AND c.url_clean IS NULL
         AND a.url_clean IN ("
       |> paste0(paste(rep("?", nrow(results)), collapse = ","), ")"),
      params = c(list(project$id), as.list(results$url_clean))
    )

    log_msg("  ", nrow(to_classify), " artigos a classificar")
    for (i in seq_len(nrow(to_classify))) {
      art <- as.list(to_classify[i, ])
      classify_article_for_project(con, project, art, examples = examples,
                                    api_key = api_key)
      if (i %% 10 == 0) log_msg("    [", i, "/", nrow(to_classify), "]")
    }
  }

  # --- Marca keyword como done ---
  project_keyword_mark(con, kw_id, "done",
                       n_search_raw       = nrow(results),
                       n_new_added        = n_new,
                       n_existing_matched = nrow(already_in_db))

  list(raw = nrow(results), new = n_new, matched = nrow(already_in_db))
}

# -----------------------------------------------------------------------------
# Roda coleta completa para o projeto: processa todas as keywords 'pending'.
# -----------------------------------------------------------------------------
#' Roda a coleta completa para um projeto
#'
#' Processa todas as keywords com status `pending` do projeto. Cada
#' keyword passa pelas fases: busca paginada → dedup → coleta de
#' fulltext → (opcional) classificação LLM. Salva tudo no banco via
#' transações idempotentes — interrupções podem ser retomadas rodando
#' a função novamente.
#'
#' @param con Conexão DBI aberta com [db_connect()].
#' @param project_id Inteiro com o id do projeto.
#' @param skip_llm Se `TRUE` (recomendado para v0.2), pula a classificação
#'   LLM. A coleta de busca + fulltext sempre roda.
#' @param n_few_shot Número de exemplos few-shot a injetar na classificação
#'   LLM (ignorado se `skip_llm = TRUE`). `0` força modo zero-shot.
#' @param reprocess Se `TRUE`, reprocessa keywords com status `done`.
#'   Padrão `FALSE` (processa só `pending`).
#'
#' @return Lista invisível com contagens (`raw`, `new`, `matched`).
#'
#' @examples
#' \dontrun{
#' con <- db_connect()
#' run_collection(con, project_id = 1, skip_llm = TRUE)
#' db_close(con)
#' }
#'
#' @seealso [project_add_keyword()] para adicionar keywords antes,
#'   [project_corpus()] para inspecionar o resultado.
#' @export
run_collection <- function(con, project_id, skip_llm = FALSE, n_few_shot = 8,
                            reprocess = FALSE) {
  project <- project_get(con, project_id)
  if (is.null(project)) stop("Projeto não encontrado: ", project_id)

  log_section(paste0("PROJETO: ", project$name))
  log_msg("Datas: ", project$date_start, " → ", project$date_end)
  log_msg("Temas: ", paste(project$themes, collapse = ", "))

  pending <- if (reprocess) {
    project_keywords(con, project_id)
  } else {
    project_keywords(con, project_id, status = "pending")
  }

  if (nrow(pending) == 0) {
    log_msg("Nada para processar — todas as keywords já estão 'done'.")
    log_msg("Use reprocess = TRUE para forçar reprocessamento.")
    return(invisible(NULL))
  }

  log_msg("Keywords a processar: ", nrow(pending))

  # API key validada antes do loop (falha rápido)
  api_key <- if (!skip_llm) get_api_key() else NULL

  run_id <- run_start(con, project_id,
                      keywords = pending$keyword, skip_llm = skip_llm)

  totals <- list(raw = 0, new = 0, matched = 0)
  ok <- TRUE
  err_msg <- NA_character_

  tryCatch(
    {
      for (i in seq_len(nrow(pending))) {
        kw_row <- pending[i, ]
        r <- process_keyword(con, project, kw_row,
                              skip_llm = skip_llm, n_few_shot = n_few_shot,
                              api_key = api_key)
        totals$raw     <- totals$raw + r$raw
        totals$new     <- totals$new + r$new
        totals$matched <- totals$matched + r$matched
      }
    },
    error = function(e) {
      ok <<- FALSE
      err_msg <<- conditionMessage(e)
      log_msg("ERRO FATAL: ", err_msg)
    }
  )

  run_finish(con, run_id,
             status = if (ok) "success" else "failed",
             articles_new = totals$new,
             articles_matched = totals$matched,
             error_msg = err_msg)

  log_section("RESUMO")
  log_msg("Bruto: ", totals$raw, " | Novos no banco: ", totals$new,
          " | Já existiam: ", totals$matched)

  invisible(totals)
}
