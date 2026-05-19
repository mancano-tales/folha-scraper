# =============================================================================
# run_app.R — lança o Shiny app a partir da raiz do repositório
# =============================================================================

# Lança o Folha Scraper Shiny app.
#
# Args:
#   port           Porta TCP (NULL = porta aleatória disponível)
#   launch.browser TRUE para abrir no navegador automaticamente
#   ...            Passado para shiny::runApp()
#
# Uso (a partir da raiz do repo):
#   source("R/run_app.R")
#   run_app()
run_app <- function(port = NULL, launch.browser = TRUE, ...) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Pacote 'shiny' não instalado. Rode: install.packages('shiny')")
  }
  for (p in c("bslib", "DT", "callr", "htmltools")) {
    if (!requireNamespace(p, quietly = TRUE)) {
      stop("Pacote '", p, "' não instalado. Rode: install.packages('", p, "')")
    }
  }
  app_dir <- file.path(getwd(), "app")
  if (!file.exists(file.path(app_dir, "app.R"))) {
    stop("app/app.R não encontrado. Rode esta função a partir da raiz do repositório.")
  }
  shiny::runApp(app_dir, port = port, launch.browser = launch.browser, ...)
}
