# =============================================================================
# db.R — conexão SQLite, migrations e helpers de baixo nível
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

# Caminho padrão do banco. Pode ser sobrescrito pela env var FOLHA_SCRAPER_DB.
db_path_default <- function() {
  custom <- Sys.getenv("FOLHA_SCRAPER_DB", unset = "")
  if (nzchar(custom)) return(custom)
  here_data <- file.path(getwd(), "data")
  if (!dir.exists(here_data)) dir.create(here_data, recursive = TRUE)
  file.path(here_data, "folha.sqlite")
}

# Localiza o diretório de migrations. O repo é clone-and-run: as migrations
# vivem em `migrations/` na raiz.
migrations_dir <- function() {
  p <- file.path(getwd(), "migrations")
  if (dir.exists(p)) return(p)
  stop("Diretório de migrations não encontrado em ", p,
       " — rode a partir da raiz do repositório.")
}

#' Abre uma conexão SQLite com o banco de dados do folha-scraper
#'
#' Conecta ao banco em `path`, ativa foreign keys e WAL mode, e aplica
#' migrations pendentes automaticamente. Idempotente — pode ser chamada
#' múltiplas vezes sem problemas.
#'
#' @param path Caminho para o arquivo SQLite. Padrão: `data/folha.sqlite`
#'   na raiz do repositório, ou o valor de `Sys.getenv("FOLHA_SCRAPER_DB")`
#'   se definido.
#'
#' @return Objeto `SQLiteConnection` (DBI).
#'
#' @seealso [db_close()] para fechar a conexão depois.
#'
#' @examples
#' \dontrun{
#' con <- db_connect()
#' DBI::dbListTables(con)
#' db_close(con)
#' }
#'
#' @export
db_connect <- function(path = db_path_default()) {
  if (!dir.exists(dirname(path))) {
    dir.create(dirname(path), recursive = TRUE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON;")
  DBI::dbExecute(con, "PRAGMA journal_mode = WAL;")
  db_migrate(con)
  con
}

#' Fecha uma conexão SQLite
#'
#' @param con Conexão retornada por [db_connect()].
#' @return `NULL` invisivelmente.
#' @export
db_close <- function(con) {
  if (!is.null(con) && DBI::dbIsValid(con)) DBI::dbDisconnect(con)
  invisible(NULL)
}

# Aplica migrations em ordem; idempotente.
db_migrate <- function(con) {
  has_version_tbl <- DBI::dbExistsTable(con, "schema_version")

  files <- list.files(migrations_dir(), pattern = "^\\d{4}_.*\\.sql$", full.names = TRUE)
  files <- sort(files)
  if (length(files) == 0) stop("Nenhum arquivo de migration encontrado.")

  applied <- integer(0)
  if (has_version_tbl) {
    applied <- DBI::dbGetQuery(con, "SELECT version FROM schema_version")$version
  }

  for (f in files) {
    version <- as.integer(sub("^(\\d{4})_.*$", "\\1", basename(f)))
    if (version %in% applied) next

    raw_lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
    # Remove comentários de linha "-- ..." (mantém o conteúdo antes do --)
    no_comments <- sub("--.*$", "", raw_lines)
    sql <- paste(no_comments, collapse = "\n")
    # Splita em statements (SQLite via DBI não aceita múltiplos por chamada)
    statements <- strsplit(sql, ";", fixed = TRUE)[[1]]
    statements <- trimws(statements)
    statements <- statements[nzchar(statements)]
    for (stmt in statements) {
      tryCatch(
        DBI::dbExecute(con, stmt),
        error = function(e) {
          stop("Falha na migration ", basename(f), ":\n  ", stmt, "\n  ", conditionMessage(e))
        }
      )
    }

    DBI::dbExecute(con, "INSERT OR IGNORE INTO schema_version (version, applied_at) VALUES (?, ?)",
              params = list(version, iso_now()))
    message("Migration aplicada: ", basename(f))
  }
  invisible(TRUE)
}

# Timestamp ISO 8601 com fuso local.
iso_now <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
}

# Slug URL-safe a partir de qualquer string.
make_slug <- function(s) {
  s |>
    stringi::stri_trans_general("Latin-ASCII") |>
    tolower() |>
    gsub("[^a-z0-9]+", "-", x = _) |>
    gsub("^-+|-+$", "", x = _)
}

# Insere artigo se ainda não existe; retorna TRUE se inseriu, FALSE se já estava.
db_upsert_article <- function(con, article) {
  existing <- DBI::dbGetQuery(con,
    "SELECT 1 FROM articles WHERE url_clean = ?",
    params = list(article$url_clean)
  )
  if (nrow(existing) > 0) {
    return(FALSE)
  }
  DBI::dbExecute(con,
    "INSERT INTO articles
      (url_clean, url, title, title_norm, date, date_raw, section, excerpt,
       full_text, era, fulltext_status, collected_at, fulltext_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      article$url_clean,
      article$url %||% article$url_clean,
      article$title %||% NA_character_,
      article$title_norm %||% NA_character_,
      as_iso_date_or_na(article$date),
      article$date_raw %||% NA_character_,
      article$section %||% NA_character_,
      article$excerpt %||% NA_character_,
      article$full_text %||% NA_character_,
      article$era %||% NA_integer_,
      article$fulltext_status %||% "pending",
      iso_now(),
      if (!is.null(article$full_text) && !is.na(article$full_text)) iso_now() else NA_character_
    )
  )
  TRUE
}

# Atualiza fulltext de um artigo existente.
db_update_fulltext <- function(con, url_clean, full_text, status = "collected", era = NA) {
  DBI::dbExecute(con,
    "UPDATE articles SET full_text = ?, fulltext_status = ?, era = COALESCE(?, era),
                         fulltext_at = ?
     WHERE url_clean = ?",
    params = list(full_text, status, era, iso_now(), url_clean)
  )
}

# Anexa um artigo a um projeto (N:N). Se já anexado, mescla matched_keywords.
db_link_article_to_project <- function(con, project_id, url_clean, keyword) {
  existing <- DBI::dbGetQuery(con,
    "SELECT matched_keywords FROM project_articles
     WHERE project_id = ? AND url_clean = ?",
    params = list(project_id, url_clean)
  )
  if (nrow(existing) == 0) {
    DBI::dbExecute(con,
      "INSERT INTO project_articles (project_id, url_clean, matched_keywords, first_matched_at)
       VALUES (?, ?, ?, ?)",
      params = list(project_id, url_clean, keyword, iso_now())
    )
    return("inserted")
  }
  current_kws <- strsplit(existing$matched_keywords[1], "; ", fixed = TRUE)[[1]]
  if (keyword %in% current_kws) return("unchanged")
  merged <- paste(c(current_kws, keyword), collapse = "; ")
  DBI::dbExecute(con,
    "UPDATE project_articles SET matched_keywords = ?
     WHERE project_id = ? AND url_clean = ?",
    params = list(merged, project_id, url_clean)
  )
  "merged"
}

# Helpers para uso ergonômico em outros módulos
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

as_iso_date_or_na <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return(NA_character_)
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  d <- suppressWarnings(as.Date(x))
  if (is.na(d)) return(NA_character_)
  format(d, "%Y-%m-%d")
}
