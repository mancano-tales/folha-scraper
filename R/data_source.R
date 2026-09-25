# data_source.R — resolvedor da convenção `.data-source` (fonte canônica)
#
# Fonte canônica: tools/data-source/data_source.R na raiz do ecossistema (mancano-repo-hub)
# Cada repositório consumidor guarda uma CÓPIA deste arquivo (ex.: R/data_source.R),
# para funcionar sozinho depois de `git clone`. Ao atualizar, recopiar; a linha
# `DATA_SOURCE_VERSION` abaixo diz qual versão cada repo tem.
#
# Convenção (plano repo-governance/plan/2026-09-24_Plano_Organizar_Google_Drive.md §10–§11):
#   .data-source na raiz do repo, uma linha por conjunto de dados:
#       # comentário
#       nome = destino:caminho/relativo
#   destino ∈ drive | ssd | local; raiz em MANCANO_<DESTINO>_ROOT
#       MANCANO_DRIVE_ROOT = G:/My Drive/mancano-tales-data
#       MANCANO_SSD_ROOT   = E:/SSD-mancano-tales-data
#   Caminhos relativos idênticos em todos os destinos; sempre "/".
#
# API:
#   data_path("nome")                 -> caminho absoluto do conjunto (erro se não existir)
#   data_path("nome", "sub/arq.csv")  -> caminho de um arquivo dentro do conjunto
#   data_path("nome", destino = "ssd")-> força outro destino (mesmo caminho relativo)
#   data_sources()                    -> data.frame com todas as linhas + se existem
#   data_cache("nome", "sub/arq.zip") -> copia arquivo/pasta para o cache LOCAL e devolve o caminho
#                                        local (recopia se faltar ou se o tamanho mudou). Use para
#                                        ler do Drive sem streaming e para extrair .zip fora do Drive.
#                                        Cache: tools::R_user_dir("mancano-data", "cache") ou
#                                        MANCANO_CACHE_ROOT. Nunca escreva de volta no Drive a
#                                        partir de uma leitura (ex.: PNADcIBGE savedir).
#                                        Extração (unzip, get_pnadc) vai para um tempdir() da
#                                        execução, apagado com on.exit, nunca para o cache.
#
# Qual .data-source é usado: argumento file= > variável MANCANO_DATA_SOURCE_FILE >
# busca subindo a partir do getwd(), que PARA na raiz do repositório git (primeira pasta
# com .git) e nunca passa dela, para não pegar o arquivo de um repositório pai.
# Comentários: linha inteira começando por "#" ou " #" depois do valor.
#
# Onde definir as variáveis: ~/.Renviron do usuário. Um .Renviron na pasta do projeto ESCONDE o
# ~/.Renviron (o R lê só um dos dois). Por isso, desde a v1.2.0, se a variável não estiver na
# sessão, o resolvedor a procura explicitamente no .Renviron do usuário (USERPROFILE, HOME,
# R_USER) e diz de onde leu: um projeto com .Renviron próprio não perde os destinos de dados.
#
# Sem fallback silencioso: variável ausente, nome desconhecido ou pasta inexistente
# param com mensagem que diz exatamente o que falta.

DATA_SOURCE_VERSION <- "1.2.0"

.ds_destinos <- c("drive", "ssd", "local")

.ds_find_file <- function(start = getwd()) {
  env <- Sys.getenv("MANCANO_DATA_SOURCE_FILE", unset = "")
  if (nzchar(env)) {
    if (!file.exists(env)) stop("MANCANO_DATA_SOURCE_FILE = '", env, "', mas o arquivo não existe.", call. = FALSE)
    return(env)
  }
  dir <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    f <- file.path(dir, ".data-source")
    if (file.exists(f)) return(f)
    if (file.exists(file.path(dir, ".git"))) break
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }
  stop("Arquivo .data-source não encontrado entre getwd() = '", start,
       "' e a raiz do repositório git. Rode a partir do repositório (ex.: projeto .Rproj ",
       "ou here::here()) ou passe file= / defina MANCANO_DATA_SOURCE_FILE.", call. = FALSE)
}

.ds_parse <- function(file) {
  linhas <- readLines(file, warn = FALSE, encoding = "UTF-8")
  linhas <- trimws(sub("(^|\\s)#.*$", "", linhas))
  linhas <- linhas[nzchar(linhas)]
  if (!length(linhas)) stop(file, " não tem nenhuma entrada.", call. = FALSE)
  m <- regmatches(linhas, regexec("^([A-Za-z0-9_.-]+)\\s*=\\s*([a-z]+):(.+)$", linhas))
  ruins <- lengths(m) == 0
  if (any(ruins)) {
    stop("Linha(s) fora do formato 'nome = destino:caminho' em ", file, ":\n  ",
         paste(linhas[ruins], collapse = "\n  "), call. = FALSE)
  }
  df <- data.frame(
    nome    = vapply(m, `[`, "", 2),
    destino = vapply(m, `[`, "", 3),
    caminho = trimws(vapply(m, `[`, "", 4)),
    stringsAsFactors = FALSE
  )
  ruim <- !df$destino %in% .ds_destinos
  if (any(ruim)) stop("Destino inválido: ", paste(unique(df$destino[ruim]), collapse = ", "),
                      ". Use: ", paste(.ds_destinos, collapse = ", "), call. = FALSE)
  if (any(grepl("(^|/)\\.\\.(/|$)", df$caminho)))
    stop("Caminho em ", file, " não pode conter '..'.", call. = FALSE)
  if (any(grepl("\\\\|^[A-Za-z]:|^/", df$caminho)))
    stop("Caminho em ", file, " deve ser relativo e usar '/'; nunca letra de unidade.", call. = FALSE)
  dup <- duplicated(df$nome)
  if (any(dup)) stop("Nome repetido em ", file, ": ", paste(df$nome[dup], collapse = ", "), call. = FALSE)
  df
}

.ds_renviron_usuario <- function(var) {
  casas <- unique(Filter(nzchar, c(Sys.getenv("USERPROFILE"), Sys.getenv("HOME"), Sys.getenv("R_USER"))))
  for (casa in casas) {
    f <- file.path(casa, ".Renviron")
    if (!file.exists(f)) next
    l <- grep(paste0("^\\s*", var, "\\s*="), readLines(f, warn = FALSE), value = TRUE)
    if (length(l)) {
      v <- gsub("^[\"']|[\"']$", "", trimws(sub("^[^=]*=", "", l[length(l)])))
      message("data_source: ", var, " lida de ", f, " (não estava definida na sessão).")
      do.call(Sys.setenv, stats::setNames(list(v), var))
      return(v)
    }
  }
  ""
}

.ds_root <- function(destino) {
  var <- paste0("MANCANO_", toupper(destino), "_ROOT")
  raiz <- Sys.getenv(var, unset = "")
  if (!nzchar(raiz)) raiz <- .ds_renviron_usuario(var)
  if (!nzchar(raiz)) {
    stop("Variável de ambiente ", var, " não definida. Defina-a nesta máquina ",
         "(ex.: no ~/.Renviron) apontando para a raiz de dados do destino '", destino, "'.",
         call. = FALSE)
  }
  if (!dir.exists(raiz)) {
    stop(var, " = '", raiz, "', mas essa pasta não existe. ",
         if (destino == "drive") "O Google Drive está montado?" else
         if (destino == "ssd") "O SSD externo está plugado?" else "",
         call. = FALSE)
  }
  sub("/+$", "", gsub("\\\\", "/", raiz))
}

data_sources <- function(file = .ds_find_file()) {
  df <- .ds_parse(file)
  df$existe <- vapply(seq_len(nrow(df)), function(i) {
    raiz <- tryCatch(.ds_root(df$destino[i]), error = function(e) NA_character_)
    !is.na(raiz) && file.exists(file.path(raiz, df$caminho[i]))
  }, logical(1))
  df
}

data_path <- function(nome, ..., destino = NULL, file = .ds_find_file()) {
  df <- .ds_parse(file)
  i <- match(nome, df$nome)
  if (is.na(i)) stop("'", nome, "' não está em ", file, ". Disponíveis: ",
                     paste(df$nome, collapse = ", "), call. = FALSE)
  dest <- if (is.null(destino)) df$destino[i] else destino
  if (!dest %in% .ds_destinos) stop("Destino inválido: '", dest, "'. Use: ",
                                    paste(.ds_destinos, collapse = ", "), call. = FALSE)
  alvo <- file.path(.ds_root(dest), df$caminho[i], ...)
  if (!file.exists(alvo)) {
    stop("'", nome, "' deveria estar em '", alvo, "' (destino ", dest,
         "), mas não existe.", call. = FALSE)
  }
  alvo
}

.ds_cache_root <- function() {
  raiz <- Sys.getenv("MANCANO_CACHE_ROOT", unset = "")
  if (!nzchar(raiz)) raiz <- tools::R_user_dir("mancano-data", which = "cache")
  gsub("\\\\", "/", raiz)
}

data_cache <- function(nome, ..., destino = NULL, file = .ds_find_file()) {
  origem <- data_path(nome, ..., destino = destino, file = file)
  df <- .ds_parse(file)
  rel <- do.call(file.path, as.list(c(df$caminho[match(nome, df$nome)], ...)))
  alvo <- file.path(.ds_cache_root(), rel)
  arquivos <- if (dir.exists(origem)) list.files(origem, recursive = TRUE, all.files = TRUE) else ""
  for (a in arquivos) {
    src <- if (nzchar(a)) file.path(origem, a) else origem
    dst <- if (nzchar(a)) file.path(alvo, a) else alvo
    if (!file.exists(dst) || file.size(dst) != file.size(src)) {
      dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(src, dst, overwrite = TRUE, copy.date = TRUE))
        stop("Falha ao copiar '", src, "' para o cache '", dst, "'.", call. = FALSE)
    }
  }
  alvo
}
