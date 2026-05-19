# =============================================================================
# export.R — exportação de um projeto para Excel (placeholder, v0.3)
# =============================================================================
#
# Esta é uma stub para a próxima versão. A exportação multi-aba (corpus,
# keywords_mapa, stats_ano, rodadas, llm_relevancia) precisa ser portada do
# `04-export.R` da pasta da tese, adaptada para ler do SQLite via DBI.
#
# Por enquanto: helper mínimo que devolve o corpus de um projeto como tibble.
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(tibble)
})

# Retorna corpus do projeto: artigos + classificações + matched_keywords.
#' Retorna o corpus de um projeto como tibble
#'
#' Junta `articles` + `project_articles` + `classifications` para
#' devolver tudo o que o projeto coletou, ordenado por data desc.
#'
#' @param con Conexão DBI.
#' @param project_id Inteiro com o id do projeto.
#'
#' @return Tibble com uma linha por artigo do projeto. Colunas incluem
#'   `url_clean`, `title`, `date`, `section`, `excerpt`, `full_text`,
#'   `era`, `fulltext_status`, `matched_keywords`, e (quando há
#'   classificação) `llm_relevant`, `llm_themes`, `llm_summary`.
#'
#' @examples
#' \dontrun{
#' con <- db_connect()
#' corpus <- project_corpus(con, 1)
#' nrow(corpus)
#' db_close(con)
#' }
#' @export
project_corpus <- function(con, project_id) {
  q <- "
    SELECT a.url_clean, a.url, a.title, a.date, a.section, a.excerpt,
           a.full_text, a.era, a.fulltext_status,
           pa.matched_keywords, pa.first_matched_at,
           c.relevant      AS llm_relevant,
           c.justification AS llm_justification,
           c.themes        AS llm_themes,
           c.summary       AS llm_summary,
           c.model         AS llm_model,
           c.classified_at AS llm_classified_at
    FROM project_articles pa
    JOIN articles a ON a.url_clean = pa.url_clean
    LEFT JOIN classifications c
      ON c.project_id = pa.project_id AND c.url_clean = pa.url_clean
    WHERE pa.project_id = ?
    ORDER BY a.date DESC, a.title ASC
  "
  DBI::dbGetQuery(con, q, params = list(project_id)) |> tibble::as_tibble()
}

# TODO v0.3 — porta de 04-export.R:
#   export_excel_project(con, project_id, file_path)
#     - aba 'corpus'          → tudo de project_corpus()
#     - aba 'keywords_mapa'   → project_keywords + contagens
#     - aba 'stats_ano'       → contagem de artigos por ano × keyword
#     - aba 'rodadas'         → log de runs do projeto
#     - aba 'llm_relevancia'  → distribuição sim/talvez/não por keyword
export_excel_project <- function(con, project_id, file_path) {
  stop("export_excel_project() ainda não implementado (v0.3). ",
       "Use project_corpus(con, project_id) por enquanto.")
}
