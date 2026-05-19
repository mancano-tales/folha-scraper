# =============================================================================
# app/global.R — bootstrap do Shiny app
# =============================================================================
# Carrega os módulos R/ e helpers reutilizados pela UI.
# Roda uma vez ao iniciar o app.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(htmltools)
})

# Raiz do repositório — usada para localizar R/ e despachar o callr.
# Quando Shiny lança o app, getwd() é a pasta app/. Subimos um nível.
.candidate <- getwd()
APP_ROOT <- if (file.exists(file.path(.candidate, "R", "db.R"))) {
  normalizePath(.candidate)
} else if (file.exists(file.path(.candidate, "..", "R", "db.R"))) {
  normalizePath(file.path(.candidate, ".."))
} else {
  stop("Não foi possível localizar a raiz do repositório (procurando por R/db.R). ",
       "cwd atual: ", .candidate)
}
rm(.candidate)

# Carrega todos os módulos R/.
for (.f in c("db.R", "utils.R", "scrape.R", "dedup.R",
             "projects.R", "llm.R", "pipeline.R", "export.R")) {
  source(file.path(APP_ROOT, "R", .f))
}

# Caminho do banco — usa o default da biblioteca (data/folha.sqlite).
DB_PATH <- db_path_default()

# Abre uma conexão de curta duração para uma operação. Sempre fecha.
with_db <- function(expr) {
  con <- db_connect(DB_PATH)
  on.exit(db_close(con), add = TRUE)
  expr_fn <- match.fun("force")
  expr_fn(eval(substitute(expr), envir = parent.frame()))
}

# Diretório de logs de runs (não-gitignorado em scope; tempdir é OK).
LOG_DIR <- file.path(tempdir(), "folha_scraper_logs")
dir.create(LOG_DIR, showWarnings = FALSE, recursive = TRUE)
