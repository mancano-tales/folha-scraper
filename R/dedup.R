# =============================================================================
# dedup.R — deduplicação fuzzy por título (Jaro-Winkler)
# =============================================================================

suppressPackageStartupMessages({
  library(stringdist)
  library(dplyr)
  library(tibble)
})

# Threshold padrão. 0.92 detecta republicações quase idênticas; 0.88 é mais agressivo.
.FUZZY_THRESHOLD <- 0.92

# Recebe novos artigos (tibble) e o conjunto de title_norms já no projeto/banco.
# Retorna:
#   $new_clean    — artigos a inserir
#   $fuzzy_dups   — artigos descartados por similaridade
dedup_fuzzy <- function(df_new, existing_title_norms, threshold = .FUZZY_THRESHOLD) {
  if (nrow(df_new) == 0) {
    return(list(new_clean = df_new, fuzzy_dups = tibble()))
  }
  if (length(existing_title_norms) == 0) {
    return(list(new_clean = df_new, fuzzy_dups = tibble()))
  }

  sim_matrix <- stringdistmatrix(
    df_new$title_norm,
    existing_title_norms,
    method = "jw",
    p      = 0.1
  )
  sim_matrix <- 1 - sim_matrix
  max_sim    <- apply(sim_matrix, 1, max)
  is_dup     <- max_sim >= threshold

  list(
    new_clean  = df_new[!is_dup, , drop = FALSE],
    fuzzy_dups = df_new[is_dup, , drop = FALSE] |>
                  mutate(fuzzy_sim = max_sim[is_dup])
  )
}

# Dedup interno de um batch: colapsa URLs duplicadas (mesma URL, múltiplas
# keywords) em uma linha consolidada com keywords concatenadas.
dedup_internal <- function(df_new) {
  if (nrow(df_new) == 0) return(df_new)
  df_new |>
    group_by(url_clean) |>
    summarise(
      title      = first(title),
      title_norm = first(title_norm),
      date       = { d <- na.omit(date); if (length(d) == 0) as.Date(NA) else min(d) },
      date_raw   = first(date_raw),
      section    = first(section),
      excerpt    = first(na.omit(c(excerpt, NA_character_))),
      url        = first(url),
      era        = first(era),
      keywords   = paste(sort(unique(keyword)), collapse = "; "),
      scraped_at = max(scraped_at),
      .groups    = "drop"
    )
}
