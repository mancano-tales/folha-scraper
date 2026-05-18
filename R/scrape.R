# =============================================================================
# scrape.R — busca paginada + coleta de fulltext
# =============================================================================

suppressPackageStartupMessages({
  library(rvest)
  library(dplyr)
  library(tibble)
  library(purrr)
})

# Configuráveis
.SCRAPE <- list(
  max_pages       = 80,    # 80 × 25 = 2000 resultados máx por keyword
  results_per_page = 25
)

# -----------------------------------------------------------------------------
# Parsing de uma página de resultados de busca
# -----------------------------------------------------------------------------
parse_search_results <- function(page_html, keyword) {
  if (is.null(page_html)) return(tibble())

  items <- page_html |> html_elements("ol.c-search > li")
  if (length(items) == 0) items <- page_html |> html_elements(".c-headline")
  if (length(items) == 0) return(tibble())

  # Estrutura: <a> é PAI de <h2>, <p>, <time>.
  tibble(
    keyword    = keyword,
    title      = items |> html_element(".c-headline__title") |> html_text2() |> str_trim(),
    url        = items |> html_element(".c-headline__content a, a[href]") |> html_attr("href"),
    excerpt    = items |> html_element(".c-headline__standfirst, .c-headline__teaser") |>
                  html_text2() |> str_trim(),
    date_raw   = items |> html_element("time") |> html_attr("datetime"),
    section    = items |> html_element(".c-kicker, .c-headline__category") |>
                  html_text2() |> str_trim(),
    scraped_at = Sys.time()
  ) |>
    filter(!is.na(title), title != "", !is.na(url))
}

# -----------------------------------------------------------------------------
# Parsing do corpo do artigo (cobre 3 eras)
# -----------------------------------------------------------------------------
parse_article_fulltext <- function(page_html) {
  if (is.null(page_html)) return(NA_character_)

  # Era 3: moderno (2010+)
  for (sel in c(".c-news__body", "div[itemprop='articleBody']",
                ".news-content", "#articleBody")) {
    body <- page_html |> html_element(sel)
    if (!is.na(body)) {
      text <- body |> html_elements("p") |> html_text2() |> str_trim() |>
        keep(\(x) nchar(x) > 30) |> paste(collapse = "\n\n")
      if (nchar(text) > 100) return(text)
    }
  }

  # Era 2: anos 2000
  body <- page_html |> html_element("div.article")
  if (!is.na(body)) {
    text <- body |> html_elements("p") |> html_text2() |> str_trim() |>
      keep(\(x) nchar(x) > 30) |> paste(collapse = "\n\n")
    if (nchar(text) > 100) return(text)
    text <- body |> html_text2() |> str_trim()
    if (nchar(text) > 100) return(text)
  }

  # Era 1/2 (anos 90 / 2000): layout em tabela arcaica, sem classes úteis,
  # texto separado por <br>. Heurística: pega o <td> com maior bloco de texto.
  # Cobre os formatos /fsp/*.htm (Folha de S.Paulo impressa, arquivo histórico).
  # Tentativas dirigidas primeiro
  for (sel in c("td[style*='padding']", "td.content")) {
    body <- page_html |> html_element(sel)
    if (!is.na(body)) {
      text <- body |> html_text2() |> str_trim()
      if (nchar(text) > 200) return(text)
    }
  }
  # Fallback heurístico: maior <td> por tamanho de texto.
  # Em /fsp/*.htm o conteúdo costuma vir prefixado/sufixado por linhas de
  # navegação ("Texto Anterior", "Próximo Texto", "Índice"); limpamos.
  tds <- page_html |> html_elements("td")
  if (length(tds) > 0) {
    texts <- vapply(tds, \(td) {
      t <- tryCatch(html_text2(td), error = function(e) "")
      str_trim(t)
    }, character(1))
    sizes <- nchar(texts)
    if (length(sizes) > 0) {
      best <- which.max(sizes)
      if (sizes[best] > 200) {
        candidate <- texts[best]
        # Remove linhas/segmentos de navegação típicos do arquivo histórico
        candidate <- candidate |>
          str_replace_all("(?m)^\\s*(Texto Anterior|Próximo Texto|Índice)[^\\n]*$", "") |>
          str_replace_all("Texto Anterior:\\s*[^\\n]*", "") |>
          str_replace_all("Próximo Texto:\\s*[^\\n]*", "") |>
          str_replace_all("(?m)^\\s*Índice\\s*$", "") |>
          str_replace_all("\\n{3,}", "\n\n") |>
          str_trim()
        # Após limpeza, descarta se for só copyright
        if (nchar(candidate) > 200 && !grepl("^Copyright", candidate)) {
          return(candidate)
        }
      }
    }
  }

  NA_character_
}

# -----------------------------------------------------------------------------
# Busca paginada por keyword
# -----------------------------------------------------------------------------
# Retorna tibble com resultados brutos da busca (sem fulltext, sem dedup ainda).
# Datas em formato Folha (DD/MM/YYYY).
search_keyword <- function(keyword,
                            date_start,
                            date_end,
                            max_pages = .SCRAPE$max_pages) {
  log_msg("Buscando: '", keyword, "' (", date_start, " → ", date_end, ")")

  all_results <- list()
  offset      <- 1
  page_num    <- 1

  repeat {
    if (page_num > max_pages) {
      log_msg("  Teto de páginas atingido (", max_pages, ").")
      break
    }

    url  <- build_search_url(keyword, date_start, date_end, offset)
    page <- safe_request(url)
    if (is.null(page)) {
      log_msg("  Falha na página ", page_num, " — parando esta keyword.")
      break
    }

    results <- parse_search_results(page, keyword)
    if (nrow(results) == 0) {
      log_msg("  Sem resultados na página ", page_num, " — fim.")
      break
    }

    all_results[[page_num]] <- results
    log_msg("  Página ", page_num, ": ", nrow(results), " resultados")

    if (nrow(results) < .SCRAPE$results_per_page) break

    offset   <- offset + .SCRAPE$results_per_page
    page_num <- page_num + 1
  }

  if (length(all_results) == 0) {
    return(tibble())
  }

  bind_rows(all_results) |>
    mutate(
      url_clean  = clean_url(url),
      date       = parse_folha_date(date_raw),
      title_norm = normalize_title(title)
    ) |>
    # Fallback: data via URL quando date_raw não foi parseável
    mutate(
      date = if_else(
        is.na(date),
        as.Date(sapply(url, extract_date_from_url), origin = "1970-01-01"),
        date
      ),
      era  = sapply(url, detect_era)
    ) |>
    filter(!is.na(url_clean), url_clean != "")
}

# -----------------------------------------------------------------------------
# Coleta de fulltext para um único artigo (não-batched)
# -----------------------------------------------------------------------------
fetch_fulltext <- function(url_clean) {
  page <- safe_request(url_clean)
  if (is.null(page)) {
    return(list(full_text = NA_character_, status = "failed"))
  }
  text <- parse_article_fulltext(page)
  if (is.na(text) || nchar(text) < 100) {
    return(list(full_text = NA_character_, status = "paywall"))
  }
  list(full_text = text, status = "collected")
}

# -----------------------------------------------------------------------------
# Inspeção (debug de seletores)
# -----------------------------------------------------------------------------
inspect_search_page <- function(keyword, date_start = "01/01/2010", date_end = "31/12/2015") {
  url  <- build_search_url(keyword, date_start, date_end, 1)
  page <- safe_request(url)
  if (is.null(page)) { message("Falha ao acessar."); return(invisible(NULL)) }

  message("\n=== INSPEÇÃO: página de busca ===\nURL: ", url)
  message("\nPrimeiro .c-headline__title:")
  print(page |> html_element(".c-headline__title"))
  message("\nPrimeiro <time>:")
  print(page |> html_element("time"))

  message("\n--- parse_search_results() ---")
  print(parse_search_results(page, keyword) |>
        select(title, date_raw, url) |> head(3))
  invisible(page)
}

inspect_article_page <- function(url) {
  page <- safe_request(url)
  if (is.null(page)) return(invisible(NULL))
  message("=== INSPEÇÃO: artigo ===\nURL: ", url)
  message("\nTexto extraído (500 chars):\n",
          str_trunc(parse_article_fulltext(page), 500))
  invisible(page)
}
