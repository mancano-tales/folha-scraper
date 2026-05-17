#!/usr/bin/env Rscript
# =============================================================================
# import_thesis_corpus.R — migra o corpus CSV da pasta da tese para o banco
#
# Uso:
#   Rscript scripts/import_thesis_corpus.R \
#     --csv "/caminho/para/corpus_master.csv" \
#     --keywords-csv "/caminho/para/keywords_processed.csv" \
#     --few-shot-csv "/caminho/para/few_shot_examples.csv" \
#     --project-name "Mancano2026-MA-Thesis"
#
# Os 3 últimos CSVs são opcionais. Se ausentes, importa só os artigos.
# =============================================================================

root <- getwd()
for (f in c("db.R", "utils.R", "scrape.R", "dedup.R", "projects.R", "llm.R")) {
  source(file.path(root, "R", f))
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(jsonlite)
})

parse_args <- function(args) {
  out <- list(); i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (startsWith(a, "--")) {
      key <- sub("^--", "", a)
      if (i == length(args) || startsWith(args[i + 1], "--")) {
        out[[key]] <- TRUE; i <- i + 1
      } else {
        out[[key]] <- args[i + 1]; i <- i + 2
      }
    } else i <- i + 1
  }
  out
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

csv_file       <- args$csv          %||% stop("Argumento --csv obrigatório")
keywords_csv   <- args$`keywords-csv`
few_shot_csv   <- args$`few-shot-csv`
project_name   <- args$`project-name` %||% "Mancano2026-MA-Thesis"
project_desc   <- args$desc %||% "Migração do corpus da dissertação de mestrado de Tales Mançano."
date_start     <- args$start %||% "1994-01-01"
date_end       <- args$end   %||% "2026-01-01"

# Temas usados na tese
default_themes <- c(
  "ProUni", "FIES", "REUNI / expansão federal", "Cotas / ação afirmativa",
  "ENEM / sistema de ingresso", "Expansão privada / EAD",
  "Desigualdade de acesso", "Financiamento público",
  "Política educacional (geral)", "Outro"
)

# -----------------------------------------------------------------------------
con <- db_connect()
on.exit(db_close(con))

log_section("IMPORTAÇÃO DA TESE")
log_msg("CSV:        ", csv_file)
log_msg("Projeto:    ", project_name)
log_msg("Banco:      ", db_path_default())

if (!file.exists(csv_file)) stop("CSV não encontrado: ", csv_file)

# --- 1. cria/recupera o projeto ---
existing <- project_get(con, project_name)
if (is.null(existing)) {
  pid <- project_create(con, name = project_name,
                         date_start = date_start, date_end = date_end,
                         themes = default_themes, description = project_desc)
  log_msg("Projeto criado: id=", pid)
} else {
  pid <- existing$id
  log_msg("Projeto já existia: id=", pid)
}

# --- 2. lê o CSV ---
corpus <- read_csv(csv_file, show_col_types = FALSE)
log_msg("Linhas no CSV: ", nrow(corpus))

# Colunas esperadas no CSV legacy:
#   article_id, date, section, title, title_norm, excerpt, full_text, url,
#   url_clean, keywords, llm_relevant, llm_justification, llm_themes,
#   llm_summary, llm_error

n_inserted <- 0
n_linked <- 0
n_classified <- 0

for (i in seq_len(nrow(corpus))) {
  row <- corpus[i, ]
  url_clean <- row$url_clean %||% clean_url(row$url)
  if (is.na(url_clean) || !nzchar(url_clean)) next

  # Inserir artigo (se ainda não existe)
  inserted <- db_upsert_article(con, list(
    url_clean       = url_clean,
    url             = row$url,
    title           = row$title,
    title_norm      = row$title_norm %||% normalize_title(row$title %||% ""),
    date            = row$date,
    date_raw        = NA_character_,
    section         = row$section,
    excerpt         = row$excerpt,
    full_text       = row$full_text,
    era             = detect_era(row$url %||% ""),
    fulltext_status = if (!is.na(row$full_text) && nchar(row$full_text %||% "") > 100)
                        "collected" else "paywall"
  ))
  if (inserted) n_inserted <- n_inserted + 1

  # Linka ao projeto, registrando as keywords originais
  keywords_str <- row$keywords %||% "(legacy)"
  first_kw <- strsplit(keywords_str, "; ", fixed = TRUE)[[1]][1] %||% "(legacy)"
  # Insere o vínculo com a primeira keyword; demais via merge
  db_link_article_to_project(con, pid, url_clean, first_kw)
  if (!is.na(keywords_str)) {
    for (kw in strsplit(keywords_str, "; ", fixed = TRUE)[[1]]) {
      db_link_article_to_project(con, pid, url_clean, kw)
    }
  }
  n_linked <- n_linked + 1

  # Classificação LLM (se existir no CSV)
  if (!is.na(row$llm_relevant) && nzchar(row$llm_relevant)) {
    classification_upsert(con, pid, url_clean,
      relevant      = row$llm_relevant,
      justification = row$llm_justification,
      themes        = row$llm_themes,
      summary       = row$llm_summary,
      model         = "deepseek-chat (legacy)",
      n_few_shot    = NA_integer_,
      error_msg     = row$llm_error
    )
    n_classified <- n_classified + 1
  }

  if (i %% 100 == 0) log_msg("  ", i, "/", nrow(corpus))
}

log_msg("Artigos inseridos:    ", n_inserted)
log_msg("Artigos linkados:     ", n_linked)
log_msg("Classificações:       ", n_classified)

# --- 3. keywords processadas ---
if (!is.null(keywords_csv) && file.exists(keywords_csv)) {
  kws <- read_csv(keywords_csv, show_col_types = FALSE)
  log_msg("\nImportando ", nrow(kws), " keywords processadas")
  for (i in seq_len(nrow(kws))) {
    kw <- kws$keyword[i]
    status <- project_add_keyword(con, pid, kw)
    if (status == "inserted") {
      # Marcar como done com as contagens originais
      kw_row <- dbGetQuery(con,
        "SELECT id FROM project_keywords WHERE project_id = ? AND keyword = ?",
        params = list(pid, kw))
      project_keyword_mark(con, kw_row$id[1], "done",
        n_search_raw       = as.integer(kws$n_search_raw[i] %||% 0),
        n_new_added        = as.integer(kws$n_new_added[i] %||% 0),
        n_existing_matched = as.integer(kws$n_existing_updated[i] %||% 0))
    }
  }
}

# --- 4. few-shot ---
if (!is.null(few_shot_csv) && file.exists(few_shot_csv)) {
  fs <- read_csv(few_shot_csv, show_col_types = FALSE)
  log_msg("\nImportando ", nrow(fs), " exemplos few-shot")
  for (i in seq_len(nrow(fs))) {
    row <- fs[i, ]
    few_shot_add(con, pid,
      title           = row$title,
      relevante       = row$relevante,
      temas           = row$temas,
      resumo          = row$resumo,
      justificativa   = row$justificativa,
      content_excerpt = row$content_excerpt,
      keywords_matched = row$keywords_matched,
      notes           = row$notes %||% NA_character_)
  }
}

log_section("IMPORTAÇÃO COMPLETA")
