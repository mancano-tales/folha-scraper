# =============================================================================
# llm.R — classificação LLM (DeepSeek), few-shot por projeto
# =============================================================================

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(glue)
})

.LLM <- list(
  provider     = "deepseek",
  base_url     = "https://api.deepseek.com/v1",
  model        = "deepseek-chat",
  cost_per_1m  = 0.14,     # USD por milhão de tokens de input
  temperature  = 0.1,
  max_retries  = 3
)

# -----------------------------------------------------------------------------
# API key
# -----------------------------------------------------------------------------
get_api_key <- function(provider = .LLM$provider) {
  env_var <- switch(provider,
    deepseek = "DEEPSEEK_API_KEY",
    stop("Provider não suportado: ", provider)
  )
  key <- Sys.getenv(env_var, unset = "")
  if (!nzchar(key) || nchar(key) < 10) {
    stop(env_var, " não definida ou inválida. Adicione ao ~/.Renviron.")
  }
  key
}

# -----------------------------------------------------------------------------
# Carrega exemplos few-shot de um projeto, com amostragem balanceada.
# Retorna tibble ou tibble vazio (= modo zero-shot).
# -----------------------------------------------------------------------------
load_few_shot <- function(con, project_id, n_few_shot = 8) {
  if (n_few_shot <= 0) return(tibble::tibble())

  all <- few_shot_list(con, project_id)
  if (nrow(all) == 0) return(tibble::tibble())

  sim    <- dplyr::filter(all, relevante == "sim")
  talvez <- dplyr::filter(all, relevante == "talvez")
  nao    <- dplyr::filter(all, relevante == "não")

  n_sim    <- min(nrow(sim),    ceiling(n_few_shot * 0.40))
  n_talvez <- min(nrow(talvez), ceiling(n_few_shot * 0.30))
  n_nao    <- min(nrow(nao),    ceiling(n_few_shot * 0.30))

  selected <- dplyr::bind_rows(
    dplyr::slice_sample(sim,    n = n_sim),
    dplyr::slice_sample(talvez, n = n_talvez),
    dplyr::slice_sample(nao,    n = n_nao)
  )
  if (nrow(selected) > n_few_shot) selected <- dplyr::slice_sample(selected, n = n_few_shot)

  log_msg("Few-shot: ", nrow(selected), " exemplos (", n_sim, " sim | ",
          n_talvez, " talvez | ", n_nao, " não)")
  selected
}

# -----------------------------------------------------------------------------
# Construção do prompt
# -----------------------------------------------------------------------------
format_one_example <- function(ex, index) {
  preview <- substr(ex$content_excerpt %||% ex$title, 1, 400)
  temas   <- if (is.na(ex$temas)) character(0) else strsplit(ex$temas, "; ", fixed = TRUE)[[1]]
  temas_json <- paste0('"', temas, '"', collapse = ", ")

  glue(
    "--- Exemplo {index} ---\n",
    "Keyword(s): {ex$keywords_matched %||% 'N/A'}\n",
    "Título: {ex$title}\n",
    "Conteúdo: {preview}\n\n",
    "Classificação correta:\n",
    "{{\n",
    '  "relevante": "{ex$relevante}",\n',
    '  "justificativa": "{ex$justificativa %||% ""}",\n',
    '  "temas": [{temas_json}],\n',
    '  "resumo": "{ex$resumo %||% ""}"\n',
    "}}"
  )
}

build_prompt <- function(project, title, content, keywords_matched,
                          examples = tibble::tibble()) {
  temas_esperados <- project$themes
  if (length(temas_esperados) == 0) temas_esperados <- "Outro"
  temas_str <- paste0("- ", temas_esperados, collapse = "\n")

  content_trimmed <- substr(content %||% title, 1, 3000)

  description <- project$description %||% "pesquisa acadêmica."
  context_block <- glue(
    "Você é um assistente de pesquisa analisando notícias da Folha de São Paulo ",
    "para o projeto '{project$name}'. Contexto: {description}\n\n",
    "Temas disponíveis para classificação:\n{temas_str}\n\n",
    "Critério de relevância:\n",
    "  sim    = trata diretamente do tema central do projeto\n",
    "  talvez = menciona o tema mas não é o foco principal da notícia\n",
    "  não    = periférico ou sem relação com a pesquisa"
  )

  few_shot_block <- ""
  if (nrow(examples) > 0) {
    examples_formatted <- vapply(seq_len(nrow(examples)),
                                  \(i) format_one_example(examples[i, ], i),
                                  character(1)) |>
      paste(collapse = "\n\n")
    few_shot_block <- glue(
      "EXEMPLOS DE CLASSIFICAÇÃO\n",
      "Use estes exemplos rotulados pelo pesquisador para calibrar seu julgamento.\n\n",
      "{examples_formatted}\n\n",
      "FIM DOS EXEMPLOS\n",
      "{strrep('-', 60)}"
    )
  }

  article_block <- glue(
    "ARTIGO PARA CLASSIFICAR\n\n",
    "Keyword(s) que encontraram este artigo: {keywords_matched}\n",
    "Título: {title}\n",
    "Conteúdo:\n{content_trimmed}"
  )

  output_block <- paste0(
    'Responda SOMENTE com JSON válido, sem texto fora do JSON:\n',
    '{\n',
    '  "relevante": "sim" | "talvez" | "não",\n',
    '  "justificativa": "1-2 frases explicando a decisão",\n',
    '  "temas": ["tema1", "tema2"],\n',
    '  "resumo": "2-3 frases descrevendo o conteúdo"\n',
    '}'
  )

  blocks <- c(context_block, few_shot_block, article_block, output_block)
  blocks <- blocks[nzchar(blocks)]
  paste(blocks, collapse = "\n\n")
}

# -----------------------------------------------------------------------------
# Chamada à API
# -----------------------------------------------------------------------------
call_llm <- function(prompt, api_key = get_api_key()) {
  tryCatch({
    resp <- request(paste0(.LLM$base_url, "/chat/completions")) |>
      req_headers(
        "Authorization" = paste("Bearer", api_key),
        "Content-Type"  = "application/json"
      ) |>
      req_body_json(list(
        model           = .LLM$model,
        temperature     = .LLM$temperature,
        response_format = list(type = "json_object"),
        messages        = list(list(role = "user", content = prompt))
      )) |>
      req_timeout(60) |>
      req_retry(max_tries = .LLM$max_retries, backoff = \(i) 10 * i) |>
      req_perform()

    raw    <- resp_body_json(resp)$choices[[1]]$message$content
    parsed <- fromJSON(raw)

    list(
      relevant      = as.character(parsed$relevante     %||% NA),
      justification = as.character(parsed$justificativa %||% NA),
      themes        = paste(parsed$temas %||% character(0), collapse = "; "),
      summary       = as.character(parsed$resumo        %||% NA),
      error         = NA_character_
    )
  }, error = function(e) {
    list(
      relevant      = NA_character_,
      justification = NA_character_,
      themes        = NA_character_,
      summary       = NA_character_,
      error         = conditionMessage(e)
    )
  })
}

# -----------------------------------------------------------------------------
# Classifica um artigo no contexto de um projeto.
# Reutiliza classificação existente se já houver (idempotente).
# -----------------------------------------------------------------------------
classify_article_for_project <- function(con, project, article,
                                          examples = tibble::tibble(),
                                          api_key = NULL,
                                          force = FALSE) {
  if (!force) {
    existing <- classification_get(con, project$id, article$url_clean)
    if (!is.null(existing) && !is.na(existing$relevant)) {
      return(invisible(existing))
    }
  }

  if (is.null(api_key)) api_key <- get_api_key()

  content <- if (!is.na(article$full_text) && nchar(article$full_text %||% "") > 100) {
    article$full_text
  } else if (!is.na(article$excerpt) && nchar(article$excerpt %||% "") > 0) {
    article$excerpt
  } else {
    article$title
  }

  # Reamostra ordem dos exemplos para evitar bias posicional
  ex_sample <- if (nrow(examples) > 0) dplyr::slice_sample(examples, n = nrow(examples)) else examples

  prompt <- build_prompt(project, article$title, content,
                          article$matched_keywords %||% "N/A", ex_sample)
  out    <- call_llm(prompt, api_key = api_key)

  classification_upsert(
    con, project$id, article$url_clean,
    relevant      = out$relevant,
    justification = out$justification,
    themes        = out$themes,
    summary       = out$summary,
    model         = .LLM$model,
    n_few_shot    = nrow(examples),
    error_msg     = out$error
  )
  Sys.sleep(stats::runif(1, 1.5, 3))
  invisible(out)
}
