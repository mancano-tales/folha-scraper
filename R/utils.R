# =============================================================================
# utils.R — logging, HTTP com retry/delay, normalização de strings, datas
# =============================================================================

suppressPackageStartupMessages({
  library(httr2)
  library(stringr)
  library(stringi)
  library(lubridate)
  library(glue)
})

# Parâmetros padrão (sobrescrevíveis por argumento explícito)
.DEFAULTS <- list(
  delay_min   = 2,
  delay_max   = 5,
  timeout_s   = 30,
  user_agent  = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  accept_lang = "pt-BR,pt;q=0.9,en;q=0.8"
)

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log_msg <- function(...) {
  ts <- format(Sys.time(), "[%H:%M:%S]")
  message(ts, " ", ...)
}

log_section <- function(title) {
  bar <- strrep("=", 60)
  message("\n", bar, "\n  ", title, "\n", bar)
}

# -----------------------------------------------------------------------------
# HTTP
# -----------------------------------------------------------------------------
safe_request <- function(url,
                          timeout    = .DEFAULTS$timeout_s,
                          delay_min  = .DEFAULTS$delay_min,
                          delay_max  = .DEFAULTS$delay_max) {
  Sys.sleep(stats::runif(1, delay_min, delay_max))
  tryCatch({
    request(url) |>
      req_headers(
        `User-Agent`      = .DEFAULTS$user_agent,
        `Accept-Language` = .DEFAULTS$accept_lang
      ) |>
      req_timeout(timeout) |>
      req_retry(max_tries = 3, backoff = \(i) 5 * i) |>
      req_perform() |>
      resp_body_html()
  }, error = function(e) {
    log_msg("ERRO HTTP: ", str_trunc(url, 70), " | ", conditionMessage(e))
    NULL
  })
}

# -----------------------------------------------------------------------------
# URL helpers
# -----------------------------------------------------------------------------
clean_url <- function(url) {
  url |>
    str_remove("\\?.*$") |>
    str_remove("/$") |>
    str_trim()
}

# Constrói URL de busca da Folha. NÃO incluir &site=folha (causa erro fatal).
build_search_url <- function(keyword, date_start, date_end, offset = 1) {
  kw_enc <- utils::URLencode(keyword, reserved = TRUE)
  glue(
    "https://search.folha.uol.com.br/search",
    "?q={kw_enc}",
    "&periodo=custom",
    "&sd={date_start}",
    "&ed={date_end}",
    "&results_count=25",
    "&sr={offset}"
  )
}

# Extrai data da URL (fallback para artigos sem <time>).
extract_date_from_url <- function(url) {
  m <- str_match(url, "/fsp/(\\d{4})/(\\d{1,2})/(\\d{1,2})/")
  if (!is.na(m[1, 2])) {
    return(as.Date(sprintf("%s-%02d-%02d",
                           m[1, 2], as.integer(m[1, 3]), as.integer(m[1, 4]))))
  }
  m2 <- str_match(basename(url), "fc(\\d{2})(\\d{2})(\\d{4})")
  if (!is.na(m2[1, 2])) {
    return(as.Date(sprintf("%s-%s-%s", m2[1, 4], m2[1, 3], m2[1, 2])))
  }
  m3 <- str_match(url, "/(20\\d{2})/(\\d{2})/[a-z]")
  if (!is.na(m3[1, 2])) {
    return(as.Date(sprintf("%s-%s-01", m3[1, 2], m3[1, 3])))
  }
  as.Date(NA)
}

# Detecta a "era" do artigo a partir da URL — útil pra debug e métricas.
detect_era <- function(url) {
  if (grepl("/fsp/19\\d{2}/", url) || grepl("/fsp/200[0-3]/", url)) return(1L)
  if (grepl("/fsp/", url) || grepl("fc\\d{8}", basename(url))) return(2L)
  3L
}

# -----------------------------------------------------------------------------
# Normalização
# -----------------------------------------------------------------------------
normalize_title <- function(title) {
  title |>
    str_to_lower() |>
    stri_trans_general("Latin-ASCII") |>
    str_remove_all("[^a-z0-9 ]") |>
    str_squish()
}

# Parser de data robusto para os formatos da Folha.
parse_folha_date <- function(date_raw) {
  if (is.null(date_raw) || all(is.na(date_raw))) return(as.Date(NA))

  parsed <- suppressWarnings(ymd_hms(date_raw, tz = "America/Sao_Paulo"))

  if (all(is.na(parsed))) {
    meses_ptbr <- c(
      jan = "jan", fev = "feb", mar = "mar", abr = "apr",
      mai = "may", jun = "jun", jul = "jul", ago = "aug",
      set = "sep", out = "oct", nov = "nov", dez = "dec"
    )
    date_en <- date_raw |>
      str_to_lower() |>
      str_remove(" às.*$") |>
      str_remove_all("\\.") |>
      str_replace_all(meses_ptbr)
    parsed <- suppressWarnings(dmy(date_en))
  }

  if (all(is.na(parsed))) parsed <- suppressWarnings(dmy(date_raw))
  if (all(is.na(parsed))) parsed <- suppressWarnings(ymd(date_raw))
  as.Date(parsed)
}

# Converte ISO date (YYYY-MM-DD) ou date para o formato que a Folha espera (DD/MM/YYYY).
to_folha_date <- function(d) {
  if (is.character(d) && grepl("^\\d{2}/\\d{2}/\\d{4}$", d)) return(d)
  parsed <- suppressWarnings(as.Date(d))
  if (is.na(parsed)) stop("Data inválida: ", d)
  format(parsed, "%d/%m/%Y")
}
