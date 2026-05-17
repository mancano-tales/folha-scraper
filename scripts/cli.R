#!/usr/bin/env Rscript
# =============================================================================
# cli.R — interface de linha de comando para o folha-scraper
#
# Uso a partir da raiz do repositório:
#   Rscript scripts/cli.R <comando> [opções]
#
# Comandos:
#   new-project    --name NOME --start YYYY-MM-DD --end YYYY-MM-DD [--themes "t1; t2"] [--desc "..."]
#   list-projects
#   show-project   --project ID_OU_NOME
#   add-keyword    --project ID_OU_NOME --keyword "..." [--start YYYY-MM-DD] [--end YYYY-MM-DD]
#   list-keywords  --project ID_OU_NOME
#   run            --project ID_OU_NOME [--skip-llm] [--few-shot N]
#   inspect-search --keyword "..." [--start DD/MM/YYYY] [--end DD/MM/YYYY]
# =============================================================================

# --- carregamento dos módulos ---
root <- normalizePath(file.path(dirname(sys.frame(1)$ofile), ".."), mustWork = FALSE)
if (!dir.exists(root) || !file.exists(file.path(root, "R", "db.R"))) {
  root <- getwd()
}
setwd(root)

for (f in c("db.R", "utils.R", "scrape.R", "dedup.R", "projects.R", "llm.R", "pipeline.R")) {
  source(file.path("R", f))
}

# --- parser de argumentos simples ---
parse_args <- function(args) {
  out <- list()
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (startsWith(a, "--")) {
      key <- sub("^--", "", a)
      # Flags booleanas (sem valor a seguir)
      if (i == length(args) || startsWith(args[i + 1], "--")) {
        out[[key]] <- TRUE
        i <- i + 1
      } else {
        out[[key]] <- args[i + 1]
        i <- i + 2
      }
    } else {
      i <- i + 1
    }
  }
  out
}

require_arg <- function(args, key) {
  if (is.null(args[[key]])) {
    stop("Argumento obrigatório ausente: --", key, call. = FALSE)
  }
  args[[key]]
}

# --- comandos ---
cmd_new_project <- function(args) {
  name   <- require_arg(args, "name")
  start  <- require_arg(args, "start")
  end    <- require_arg(args, "end")
  themes <- if (!is.null(args$themes)) strsplit(args$themes, "; ", fixed = TRUE)[[1]]
            else character(0)
  desc   <- args$desc

  con <- db_connect()
  on.exit(db_close(con))
  id <- project_create(con, name = name, date_start = start, date_end = end,
                       themes = themes, description = desc)
  cat("Projeto criado: id=", id, " name='", name, "'\n", sep = "")
}

cmd_list_projects <- function(args) {
  con <- db_connect()
  on.exit(db_close(con))
  df <- project_list(con, include_archived = !is.null(args$all))
  if (nrow(df) == 0) {
    cat("(nenhum projeto)\n")
    return(invisible(NULL))
  }
  print(df, n = Inf)
}

cmd_show_project <- function(args) {
  con <- db_connect()
  on.exit(db_close(con))
  pid_or_name <- require_arg(args, "project")
  proj <- project_get(con, pid_or_name)
  if (is.null(proj)) {
    cat("Projeto não encontrado:", pid_or_name, "\n")
    return(invisible(NULL))
  }
  cat("ID:          ", proj$id, "\n", sep = "")
  cat("Nome:        ", proj$name, "\n", sep = "")
  cat("Slug:        ", proj$slug, "\n", sep = "")
  cat("Status:      ", proj$status, "\n", sep = "")
  cat("Datas:       ", proj$date_start, " → ", proj$date_end, "\n", sep = "")
  cat("Temas:       ", paste(proj$themes, collapse = ", "), "\n", sep = "")
  cat("Descrição:   ", proj$description %||% "(sem descrição)", "\n", sep = "")
  cat("\n--- KEYWORDS ---\n")
  print(project_keywords(con, proj$id), n = Inf)
}

cmd_add_keyword <- function(args) {
  con <- db_connect()
  on.exit(db_close(con))
  pid_or_name <- require_arg(args, "project")
  proj <- project_get(con, pid_or_name)
  if (is.null(proj)) stop("Projeto não encontrado: ", pid_or_name, call. = FALSE)
  kw <- require_arg(args, "keyword")

  ds <- if (!is.null(args$start)) args$start else NA
  de <- if (!is.null(args$end))   args$end   else NA

  status <- project_add_keyword(con, proj$id, kw,
                                 date_start_override = ds, date_end_override = de)
  cat("Keyword '", kw, "': ", status, "\n", sep = "")
}

cmd_list_keywords <- function(args) {
  con <- db_connect()
  on.exit(db_close(con))
  pid_or_name <- require_arg(args, "project")
  proj <- project_get(con, pid_or_name)
  if (is.null(proj)) stop("Projeto não encontrado: ", pid_or_name, call. = FALSE)
  print(project_keywords(con, proj$id), n = Inf)
}

cmd_run <- function(args) {
  con <- db_connect()
  on.exit(db_close(con))
  pid_or_name <- require_arg(args, "project")
  proj <- project_get(con, pid_or_name)
  if (is.null(proj)) stop("Projeto não encontrado: ", pid_or_name, call. = FALSE)

  skip_llm   <- isTRUE(args$`skip-llm`)
  n_few_shot <- if (!is.null(args$`few-shot`)) as.integer(args$`few-shot`) else 8L
  reprocess  <- isTRUE(args$reprocess)

  run_collection(con, proj$id,
                  skip_llm = skip_llm,
                  n_few_shot = n_few_shot,
                  reprocess = reprocess)
}

cmd_inspect_search <- function(args) {
  kw <- require_arg(args, "keyword")
  ds <- args$start %||% "01/01/2010"
  de <- args$end   %||% "31/12/2015"
  inspect_search_page(kw, ds, de)
}

# --- dispatch ---
main <- function() {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) == 0) {
    cat("Uso: Rscript scripts/cli.R <comando> [opções]\n",
        "Comandos: new-project, list-projects, show-project, add-keyword,\n",
        "          list-keywords, run, inspect-search\n", sep = "")
    quit(status = 1)
  }
  cmd <- argv[1]
  args <- parse_args(argv[-1])

  switch(cmd,
    "new-project"    = cmd_new_project(args),
    "list-projects"  = cmd_list_projects(args),
    "show-project"   = cmd_show_project(args),
    "add-keyword"    = cmd_add_keyword(args),
    "list-keywords"  = cmd_list_keywords(args),
    "run"            = cmd_run(args),
    "inspect-search" = cmd_inspect_search(args),
    stop("Comando desconhecido: ", cmd, call. = FALSE)
  )
}

main()
