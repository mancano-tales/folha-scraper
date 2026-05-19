#!/usr/bin/env Rscript
# =============================================================================
# Lança o Shiny app via Rscript.
#
# Uso (a partir da raiz do repo):
#   Rscript scripts/run_app.R [--port 4321] [--no-browser]
# =============================================================================

# Resolve script dir e seta cwd na raiz do repositório
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  }
  getwd()
}
setwd(normalizePath(file.path(get_script_dir(), ".."), mustWork = FALSE))

source("R/run_app.R")

# Parse args
args <- commandArgs(trailingOnly = TRUE)
port <- NULL
launch_browser <- TRUE
i <- 1
while (i <= length(args)) {
  a <- args[i]
  if (a == "--port" && i < length(args)) {
    port <- as.integer(args[i + 1]); i <- i + 2
  } else if (a == "--no-browser") {
    launch_browser <- FALSE; i <- i + 1
  } else {
    i <- i + 1
  }
}

run_app(port = port, launch.browser = launch_browser)
