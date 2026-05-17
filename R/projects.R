# =============================================================================
# projects.R — CRUD de projetos, keywords, classificações, few-shot
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(jsonlite)
  library(dplyr)
  library(tibble)
})

# -----------------------------------------------------------------------------
# Projects
# -----------------------------------------------------------------------------
project_create <- function(con, name, date_start, date_end,
                            themes = character(0),
                            description = NA_character_) {
  stopifnot(nchar(name) > 0)
  slug    <- make_slug(name)
  now     <- iso_now()
  ds_iso  <- as_iso_date_or_na(date_start)
  de_iso  <- as_iso_date_or_na(date_end)
  if (is.na(ds_iso) || is.na(de_iso)) {
    stop("date_start e date_end devem ser parseáveis como Date.")
  }
  themes_json <- toJSON(themes, auto_unbox = FALSE)

  dbExecute(con,
    "INSERT INTO projects
      (name, slug, description, date_start, date_end, themes_json, status, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)",
    params = list(name, slug, description %||% NA_character_,
                  ds_iso, de_iso, themes_json, now, now)
  )

  dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
}

project_list <- function(con, include_archived = FALSE) {
  q <- "SELECT p.id, p.name, p.slug, p.date_start, p.date_end, p.status,
               p.created_at,
               (SELECT COUNT(*) FROM project_keywords k WHERE k.project_id = p.id) AS n_keywords,
               (SELECT COUNT(*) FROM project_articles a WHERE a.project_id = p.id) AS n_articles
        FROM projects p"
  if (!include_archived) q <- paste(q, "WHERE p.status = 'active'")
  q <- paste(q, "ORDER BY p.updated_at DESC")
  dbGetQuery(con, q) |> as_tibble()
}

project_get <- function(con, id_or_name) {
  if (is.numeric(id_or_name)) {
    res <- dbGetQuery(con, "SELECT * FROM projects WHERE id = ?", params = list(id_or_name))
  } else {
    res <- dbGetQuery(con, "SELECT * FROM projects WHERE name = ? OR slug = ?",
                      params = list(id_or_name, id_or_name))
  }
  if (nrow(res) == 0) return(NULL)
  out <- as.list(res[1, ])
  out$themes <- if (!is.na(out$themes_json)) fromJSON(out$themes_json) else character(0)
  out
}

project_archive <- function(con, project_id) {
  dbExecute(con, "UPDATE projects SET status = 'archived', updated_at = ? WHERE id = ?",
            params = list(iso_now(), project_id))
}

# -----------------------------------------------------------------------------
# Keywords
# -----------------------------------------------------------------------------
project_add_keyword <- function(con, project_id, keyword,
                                 date_start_override = NA, date_end_override = NA) {
  ds <- if (is.na(date_start_override)) NA_character_ else as_iso_date_or_na(date_start_override)
  de <- if (is.na(date_end_override))   NA_character_ else as_iso_date_or_na(date_end_override)

  tryCatch(
    {
      dbExecute(con,
        "INSERT INTO project_keywords
          (project_id, keyword, date_start_override, date_end_override, status, added_at)
         VALUES (?, ?, ?, ?, 'pending', ?)",
        params = list(project_id, keyword, ds, de, iso_now())
      )
      dbExecute(con, "UPDATE projects SET updated_at = ? WHERE id = ?",
                params = list(iso_now(), project_id))
      "inserted"
    },
    error = function(e) {
      if (grepl("UNIQUE", conditionMessage(e))) "already_exists"
      else stop(e)
    }
  )
}

project_keywords <- function(con, project_id, status = NULL) {
  q <- "SELECT * FROM project_keywords WHERE project_id = ?"
  params <- list(project_id)
  if (!is.null(status)) {
    q <- paste(q, "AND status = ?")
    params <- c(params, list(status))
  }
  q <- paste(q, "ORDER BY added_at ASC")
  dbGetQuery(con, q, params = params) |> as_tibble()
}

project_keyword_mark <- function(con, keyword_id, status,
                                  n_search_raw = NULL, n_new_added = NULL,
                                  n_existing_matched = NULL, error_msg = NULL) {
  sets <- "status = ?"
  params <- list(status)
  if (!is.null(n_search_raw)) {
    sets <- paste(sets, ", n_search_raw = ?")
    params <- c(params, list(n_search_raw))
  }
  if (!is.null(n_new_added)) {
    sets <- paste(sets, ", n_new_added = ?")
    params <- c(params, list(n_new_added))
  }
  if (!is.null(n_existing_matched)) {
    sets <- paste(sets, ", n_existing_matched = ?")
    params <- c(params, list(n_existing_matched))
  }
  if (!is.null(error_msg)) {
    sets <- paste(sets, ", error_msg = ?")
    params <- c(params, list(error_msg))
  }
  if (status %in% c("done", "failed")) {
    sets <- paste(sets, ", processed_at = ?")
    params <- c(params, list(iso_now()))
  }
  params <- c(params, list(keyword_id))
  dbExecute(con, paste("UPDATE project_keywords SET", sets, "WHERE id = ?"),
            params = params)
}

# Resolve as datas efetivas de uma keyword (override > projeto), formato Folha.
keyword_effective_dates <- function(con, project_id, keyword_id) {
  kw_row <- dbGetQuery(con,
    "SELECT k.date_start_override, k.date_end_override,
            p.date_start, p.date_end
     FROM project_keywords k
     JOIN projects p ON p.id = k.project_id
     WHERE k.id = ?",
    params = list(keyword_id)
  )
  if (nrow(kw_row) == 0) stop("keyword_id não encontrada: ", keyword_id)

  ds <- kw_row$date_start_override[1] %||% kw_row$date_start[1]
  de <- kw_row$date_end_override[1]   %||% kw_row$date_end[1]
  list(start = to_folha_date(ds), end = to_folha_date(de))
}

# -----------------------------------------------------------------------------
# Classifications (LLM) — leitura/escrita
# -----------------------------------------------------------------------------
classification_get <- function(con, project_id, url_clean) {
  res <- dbGetQuery(con,
    "SELECT * FROM classifications WHERE project_id = ? AND url_clean = ?",
    params = list(project_id, url_clean))
  if (nrow(res) == 0) NULL else as.list(res[1, ])
}

classification_upsert <- function(con, project_id, url_clean,
                                   relevant, justification, themes, summary,
                                   model = NA, n_few_shot = NA, error_msg = NA) {
  dbExecute(con, "DELETE FROM classifications WHERE project_id = ? AND url_clean = ?",
            params = list(project_id, url_clean))
  dbExecute(con,
    "INSERT INTO classifications
      (project_id, url_clean, relevant, justification, themes, summary,
       model, n_few_shot, error_msg, classified_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(project_id, url_clean, relevant, justification, themes,
                  summary, model, n_few_shot, error_msg, iso_now())
  )
}

# -----------------------------------------------------------------------------
# Few-shot examples
# -----------------------------------------------------------------------------
few_shot_list <- function(con, project_id) {
  dbGetQuery(con, "SELECT * FROM few_shot_examples WHERE project_id = ? ORDER BY added_at",
             params = list(project_id)) |> as_tibble()
}

few_shot_add <- function(con, project_id, title, relevante,
                          temas = NA, resumo = NA, justificativa = NA,
                          url_clean = NA, content_excerpt = NA,
                          keywords_matched = NA, notes = NA) {
  dbExecute(con,
    "INSERT INTO few_shot_examples
      (project_id, url_clean, title, content_excerpt, keywords_matched,
       relevante, justificativa, temas, resumo, notes, added_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(project_id, url_clean, title, content_excerpt,
                  keywords_matched, relevante, justificativa, temas, resumo,
                  notes, iso_now())
  )
}

# -----------------------------------------------------------------------------
# Runs
# -----------------------------------------------------------------------------
run_start <- function(con, project_id, keywords, skip_llm = FALSE) {
  dbExecute(con,
    "INSERT INTO runs (project_id, started_at, status, phase, keywords_run, skip_llm)
     VALUES (?, ?, 'running', 'search', ?, ?)",
    params = list(project_id, iso_now(),
                  toJSON(keywords, auto_unbox = FALSE),
                  as.integer(skip_llm))
  )
  dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[1]
}

run_finish <- function(con, run_id, status = "success",
                       articles_new = 0, articles_matched = 0,
                       error_msg = NA) {
  dbExecute(con,
    "UPDATE runs SET finished_at = ?, status = ?,
                     articles_new = ?, articles_matched = ?, error_msg = ?
     WHERE id = ?",
    params = list(iso_now(), status, articles_new, articles_matched,
                  error_msg, run_id)
  )
}

run_phase <- function(con, run_id, phase) {
  dbExecute(con, "UPDATE runs SET phase = ? WHERE id = ?",
            params = list(phase, run_id))
}
