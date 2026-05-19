# =============================================================================
# run_app.R — lança o Shiny app a partir da raiz do repositório
# =============================================================================

#' Lança o Shiny app do Folha Scraper
#'
#' Abre a interface gráfica local com 3 abas: Projetos, Projeto atual,
#' e Sobre. A coleta roda em processo separado via [callr::r_bg()] e o
#' log aparece em tempo real na aba Coleta.
#'
#' @param port Porta TCP. `NULL` (padrão) escolhe uma porta aleatória
#'   disponível.
#' @param launch.browser Se `TRUE` (padrão), abre o app no navegador
#'   padrão do sistema.
#' @param ... Argumentos adicionais passados para [shiny::runApp()]
#'   (ex.: `host`, `quiet`).
#'
#' @return Invocada por efeito colateral. Retorna o valor de
#'   [shiny::runApp()] invisivelmente.
#'
#' @examples
#' \dontrun{
#' source("R/run_app.R")
#' run_app()
#' run_app(port = 4321, launch.browser = FALSE)
#' }
#'
#' @export
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
