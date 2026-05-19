# =============================================================================
# Folha Scraper — Shiny App (v0.2 MVP, sem features LLM)
# =============================================================================
# Para rodar: shiny::runApp("app") a partir da raiz do repo, ou
#             folhascraper::run_app() se carregou via R/run_app.R.
# =============================================================================

# global.R já carregou shiny, bslib, DT, htmltools, e os módulos R/.
# Garantia caso este arquivo seja sourceado isolado:
if (!exists("APP_ROOT")) source(file.path(getwd(), "global.R"))

# -----------------------------------------------------------------------------
# Helpers de DB e formatação
# -----------------------------------------------------------------------------
db_op <- function(fn) {
  con <- db_connect(DB_PATH)
  on.exit(db_close(con))
  fn(con)
}

fmt_date_br <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("")
  d <- suppressWarnings(as.Date(x))
  if (is.na(d)) return(as.character(x))
  format(d, "%d/%m/%Y")
}

fmt_int <- function(x) format(x %||% 0, big.mark = ".", decimal.mark = ",", scientific = FALSE)

# Status humano-legível com cor
status_badge <- function(s) {
  pal <- list(
    pending    = list(bg = "#f3f4f6", fg = "#374151", label = "pendente"),
    searching  = list(bg = "#dbeafe", fg = "#1e3a8a", label = "buscando"),
    done       = list(bg = "#d1fae5", fg = "#065f46", label = "concluída"),
    failed     = list(bg = "#fee2e2", fg = "#991b1b", label = "falhou"),
    collected  = list(bg = "#d1fae5", fg = "#065f46", label = "coletado"),
    paywall    = list(bg = "#fef3c7", fg = "#92400e", label = "paywall"),
    active     = list(bg = "#d1fae5", fg = "#065f46", label = "ativo"),
    archived   = list(bg = "#f3f4f6", fg = "#374151", label = "arquivado")
  )
  p <- pal[[s]] %||% list(bg = "#e5e7eb", fg = "#1f2937", label = s)
  sprintf(
    '<span style="background:%s;color:%s;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600">%s</span>',
    p$bg, p$fg, p$label
  )
}

# Card simples de estatística
stat_card <- function(label, value, sub = NULL, color = "#1a3a5c") {
  bslib::card(
    bslib::card_body(
      style = "padding: 14px;",
      div(style = sprintf("color:%s;font-size:11px;text-transform:uppercase;letter-spacing:.05em;font-weight:600;", color),
          label),
      div(style = "font-size:28px;font-weight:700;line-height:1.2;margin-top:4px;",
          value),
      if (!is.null(sub)) div(style = "color:#6b7280;font-size:12px;margin-top:2px;", sub)
    )
  )
}

# -----------------------------------------------------------------------------
# UI: forms para modais (extraídos como funções pra reuso)
# -----------------------------------------------------------------------------
ui_new_project_form <- function() {
  tagList(
    textInput("np_name", "Nome do projeto", placeholder = "ex.: Reforma do ProUni"),
    fluidRow(
      column(6, dateInput("np_start", "Data inicial", value = "2003-01-01",
                          format = "dd/mm/yyyy", language = "pt-BR")),
      column(6, dateInput("np_end", "Data final", value = Sys.Date(),
                          format = "dd/mm/yyyy", language = "pt-BR"))
    ),
    textAreaInput("np_themes", "Temas (um por linha)",
                  rows = 5,
                  placeholder = "ProUni\nFIES\nCotas / ação afirmativa"),
    textAreaInput("np_desc", "Descrição (opcional)", rows = 3,
                  placeholder = "Contexto da pesquisa, perguntas, etc.")
  )
}

ui_add_keyword_form <- function() {
  tagList(
    textInput("ak_keyword", "Keyword",
              placeholder = "ex.: ProUni  |  \"financiamento estudantil\""),
    helpText("Aspas escapadas (\\\") viram busca exata na Folha. ",
             "Múltiplas palavras = AND implícito."),
    fluidRow(
      column(6, dateInput("ak_start", "Data inicial (opcional)",
                          value = NA, format = "dd/mm/yyyy", language = "pt-BR")),
      column(6, dateInput("ak_end", "Data final (opcional)",
                          value = NA, format = "dd/mm/yyyy", language = "pt-BR"))
    ),
    helpText("Se vazias, usa as datas do projeto.")
  )
}

# -----------------------------------------------------------------------------
# UI principal
# -----------------------------------------------------------------------------
custom_css <- HTML("
  .stat-row { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 16px; }
  .stat-row > .card { flex: 1 1 160px; min-width: 160px; }
  .run-log {
    background: #0f172a;
    color: #e2e8f0;
    padding: 14px;
    border-radius: 6px;
    font-family: 'Cascadia Code', 'Consolas', 'Monaco', monospace;
    font-size: 12px;
    line-height: 1.45;
    max-height: 480px;
    overflow-y: auto;
    white-space: pre-wrap;
    word-wrap: break-word;
  }
  .article-fulltext {
    background: #fafaf9;
    padding: 14px;
    border-radius: 6px;
    font-family: 'Georgia', serif;
    font-size: 14px;
    line-height: 1.55;
    max-height: 60vh;
    overflow-y: auto;
    white-space: pre-wrap;
  }
  .navbar-brand { font-weight: 700; }
  .nav-pills .nav-link.active { background-color: #1a3a5c !important; }
  .footer-note { color:#6b7280; font-size:12px; margin-top:24px; padding-top:12px; border-top:1px solid #e5e7eb; }
")

ui <- bslib::page_navbar(
  title = span("Folha Scraper ", tags$small(style="opacity:.6;font-weight:400", "v0.2")),
  id = "main_nav",
  theme = bslib::bs_theme(version = 5, primary = "#1a3a5c"),
  navbar_options = bslib::navbar_options(bg = "#1a3a5c"),
  fillable = FALSE,
  header = tags$head(tags$style(custom_css)),

  # =========================================================================
  # ABA 1 — Projetos
  # =========================================================================
  bslib::nav_panel(
    title = "Projetos", value = "tab_projects",
    icon  = NULL,
    div(style = "padding: 20px 8px;",
      div(style = "display:flex; justify-content:space-between; align-items:center; margin-bottom:16px;",
        h3("Projetos de pesquisa", style = "margin:0;"),
        actionButton("btn_new_project", "+ Novo projeto",
                     class = "btn-primary", icon = icon("plus"))
      ),
      p(style = "color:#6b7280;",
        "Cada projeto define keywords, datas e temas de uma pesquisa. ",
        "Artigos são coletados uma vez e compartilhados entre projetos."),
      DT::DTOutput("projects_table"),
      p(class = "footer-note",
        "Dica: clique numa linha para abrir o projeto.")
    )
  ),

  # =========================================================================
  # ABA 2 — Projeto Atual
  # =========================================================================
  bslib::nav_panel(
    title = "Projeto atual", value = "tab_project",
    icon  = NULL,
    div(style = "padding: 20px 8px;",
      uiOutput("project_header"),
      uiOutput("project_body")
    )
  ),

  # =========================================================================
  # ABA 3 — Sobre
  # =========================================================================
  bslib::nav_panel(
    title = "Sobre", value = "tab_about",
    icon  = NULL,
    div(style = "padding: 20px 16px; max-width: 760px;",
      h3("Folha Scraper"),
      p("Coletor sistemático de notícias da Folha de São Paulo para pesquisa acadêmica. ",
        "Suporta múltiplos projetos lado a lado, compartilhando um banco de artigos ",
        "coletados (URL-keyed)."),
      h5("Origem"),
      p("Spinoff do pipeline desenvolvido para a dissertação de mestrado ",
        em("Mancano2026-MA-Thesis"), ". O código da tese permanece congelado como ",
        "artefato; este repositório é a versão genérica."),
      h5("Versão atual (v0.2)"),
      tags$ul(
        tags$li("Criação e gerenciamento de projetos"),
        tags$li("Adição incremental de keywords (com datas opcionais por keyword)"),
        tags$li("Coleta de busca + fulltext (cobre 3 eras de layout da Folha)"),
        tags$li("Deduplicação por URL + fuzzy por título"),
        tags$li("Navegação do corpus com filtros")
      ),
      h5("Próximas versões"),
      tags$ul(
        tags$li("v0.2.x — Classificação LLM por projeto, anotação few-shot no app"),
        tags$li("v0.3 — Exportação Excel multi-aba"),
        tags$li("v0.4 — Auditoria de classificações LLM")
      ),
      h5("Repositório"),
      p(tags$a(href = "https://github.com/mancano-tales/folha-scraper",
               target = "_blank", "github.com/mancano-tales/folha-scraper")),
      p(class = "footer-note",
        "Banco local em: ", tags$code(DB_PATH))
    )
  )
)

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------
server <- function(input, output, session) {

  # ---------------------------------------------------------------------------
  # Estado reativo
  # ---------------------------------------------------------------------------
  selected_project_id <- reactiveVal(NULL)
  projects_refresh    <- reactiveVal(0L)
  keywords_refresh    <- reactiveVal(0L)
  corpus_refresh      <- reactiveVal(0L)
  run_proc            <- reactiveVal(NULL)
  run_log_file        <- reactiveVal(NULL)
  run_finished_at     <- reactiveVal(NULL)  # marca completion para notificar 1x

  # ===========================================================================
  # ABA PROJETOS
  # ===========================================================================
  projects_df <- reactive({
    projects_refresh()
    db_op(\(con) project_list(con, include_archived = TRUE))
  })

  output$projects_table <- DT::renderDT({
    df <- projects_df()
    if (nrow(df) == 0) {
      return(DT::datatable(
        data.frame(Mensagem = "Nenhum projeto. Use o botão + Novo projeto para criar."),
        options = list(dom = "t", paging = FALSE, info = FALSE, ordering = FALSE),
        rownames = FALSE
      ))
    }
    show <- data.frame(
      ID        = df$id,
      Nome      = df$name,
      Início    = fmt_date_br(df$date_start),
      Fim       = fmt_date_br(df$date_end),
      Status    = vapply(df$status, status_badge, character(1)),
      Keywords  = fmt_int(df$n_keywords),
      Artigos   = fmt_int(df$n_articles),
      stringsAsFactors = FALSE
    )
    DT::datatable(
      show,
      selection = "single",
      escape    = FALSE,
      rownames  = FALSE,
      class     = "compact stripe hover",
      options   = list(
        dom = "ftip", pageLength = 15,
        language = list(
          search = "Filtrar:",
          paginate = list(`next` = "→", previous = "←"),
          info = "Mostrando _START_ a _END_ de _TOTAL_",
          zeroRecords = "Nenhum projeto encontrado.",
          emptyTable  = "Nenhum projeto cadastrado."
        ),
        columnDefs = list(
          list(className = "dt-right", targets = c(0, 5, 6))
        )
      )
    )
  })

  observeEvent(input$projects_table_rows_selected, {
    sel <- input$projects_table_rows_selected
    if (length(sel) == 0) return()
    df <- projects_df()
    if (nrow(df) == 0) return()
    pid <- df$id[sel]
    selected_project_id(pid)
    updateNavbarPage(session, "main_nav", selected = "tab_project")
  })

  # ---- Modal: novo projeto ----
  observeEvent(input$btn_new_project, {
    showModal(modalDialog(
      title = "Novo projeto",
      ui_new_project_form(),
      easyClose = TRUE,
      size  = "m",
      footer = tagList(
        modalButton("Cancelar"),
        actionButton("np_submit", "Criar projeto", class = "btn-primary")
      )
    ))
  })

  observeEvent(input$np_submit, {
    name <- trimws(input$np_name %||% "")
    if (!nzchar(name)) {
      showNotification("Nome do projeto é obrigatório.", type = "error"); return()
    }
    ds <- input$np_start; de <- input$np_end
    if (is.null(ds) || is.null(de) || is.na(ds) || is.na(de)) {
      showNotification("Datas inicial e final são obrigatórias.", type = "error"); return()
    }
    if (ds > de) {
      showNotification("Data inicial deve ser anterior à data final.", type = "error"); return()
    }
    themes_raw <- input$np_themes %||% ""
    themes_vec <- strsplit(themes_raw, "\n", fixed = TRUE)[[1]] |> trimws()
    themes_vec <- themes_vec[nzchar(themes_vec)]
    desc <- trimws(input$np_desc %||% "")
    if (!nzchar(desc)) desc <- NA_character_

    pid <- tryCatch(
      db_op(\(con) project_create(con,
        name = name, date_start = ds, date_end = de,
        themes = themes_vec, description = desc)),
      error = function(e) {
        showNotification(paste0("Erro: ", conditionMessage(e)), type = "error")
        NULL
      }
    )
    if (is.null(pid)) return()
    removeModal()
    projects_refresh(projects_refresh() + 1L)
    selected_project_id(pid)
    showNotification(paste0("Projeto '", name, "' criado (id=", pid, ")."),
                     type = "message", duration = 4)
    updateNavbarPage(session, "main_nav", selected = "tab_project")
  })

  # ===========================================================================
  # ABA PROJETO ATUAL — header + body
  # ===========================================================================
  current_project <- reactive({
    pid <- selected_project_id()
    if (is.null(pid)) return(NULL)
    projects_refresh()
    db_op(\(con) project_get(con, pid))
  })

  # Header sempre presente (ou empty state)
  output$project_header <- renderUI({
    p <- current_project()
    if (is.null(p)) {
      return(div(class = "alert alert-info",
                 "Selecione um projeto na aba ", strong("Projetos"),
                 " para ver detalhes aqui."))
    }
    tagList(
      div(style = "display:flex;justify-content:space-between;align-items:flex-start;gap:16px;margin-bottom:8px;",
        div(
          h3(p$name, style = "margin:0;"),
          div(style = "color:#6b7280;font-size:13px;margin-top:4px;",
              fmt_date_br(p$date_start), " → ", fmt_date_br(p$date_end),
              HTML(" &nbsp;·&nbsp; "),
              HTML(status_badge(p$status))),
          if (!is.na(p$description) && nzchar(p$description))
            div(style = "margin-top:8px;max-width:760px;color:#374151;", p$description)
        )
      )
    )
  })

  # Body: 4 sub-abas
  output$project_body <- renderUI({
    p <- current_project()
    if (is.null(p)) return(NULL)
    bslib::navset_pill(
      bslib::nav_panel("Visão geral",  value = "sub_overview",
                       uiOutput("subtab_overview")),
      bslib::nav_panel("Keywords",     value = "sub_keywords",
                       uiOutput("subtab_keywords")),
      bslib::nav_panel("Coleta",       value = "sub_run",
                       uiOutput("subtab_run")),
      bslib::nav_panel("Corpus",       value = "sub_corpus",
                       uiOutput("subtab_corpus")),
      id = "project_subnav"
    )
  })

  # ---------------------------------------------------------------------------
  # Sub-aba: Visão geral
  # ---------------------------------------------------------------------------
  project_stats <- reactive({
    pid <- selected_project_id(); req(pid)
    keywords_refresh(); corpus_refresh()
    db_op(\(con) {
      kw <- project_keywords(con, pid)
      n_articles <- DBI::dbGetQuery(con,
        "SELECT COUNT(*) AS n FROM project_articles WHERE project_id = ?",
        params = list(pid))$n
      n_ft <- DBI::dbGetQuery(con,
        "SELECT COUNT(*) AS n FROM project_articles pa
         JOIN articles a ON a.url_clean = pa.url_clean
         WHERE pa.project_id = ? AND a.fulltext_status = 'collected'",
        params = list(pid))$n
      runs <- DBI::dbGetQuery(con,
        "SELECT id, started_at, finished_at, status, articles_new, articles_matched,
                skip_llm, error_msg
         FROM runs WHERE project_id = ? ORDER BY started_at DESC LIMIT 20",
        params = list(pid))
      list(
        kw_total = nrow(kw),
        kw_done  = sum(kw$status == "done", na.rm = TRUE),
        kw_pending = sum(kw$status == "pending", na.rm = TRUE),
        n_articles = n_articles,
        n_ft = n_ft,
        runs = runs
      )
    })
  })

  output$subtab_overview <- renderUI({
    s <- project_stats()
    pct_ft <- if (s$n_articles > 0) round(100 * s$n_ft / s$n_articles, 1) else 0
    runs <- s$runs
    runs_table <- if (nrow(runs) == 0) {
      p(em("Nenhuma rodada registrada ainda. Vá em ", strong("Coleta"),
           " para iniciar."))
    } else {
      tbl <- data.frame(
        ID = runs$id,
        Início = format(as.POSIXct(runs$started_at), "%d/%m/%Y %H:%M"),
        Fim = ifelse(is.na(runs$finished_at), "—",
                      format(as.POSIXct(runs$finished_at), "%H:%M:%S")),
        Status = vapply(runs$status, status_badge, character(1)),
        `Artigos novos` = fmt_int(runs$articles_new),
        `Já existiam` = fmt_int(runs$articles_matched),
        `Sem LLM` = ifelse(runs$skip_llm == 1, "sim", "não"),
        check.names = FALSE, stringsAsFactors = FALSE
      )
      DT::datatable(
        tbl, escape = FALSE, rownames = FALSE,
        options = list(dom = "tip", pageLength = 10, ordering = FALSE,
                       language = list(info = "Rodadas: _START_–_END_ de _TOTAL_",
                                       paginate = list(`next`="→", previous="←")))
      )
    }

    tagList(
      div(class = "stat-row",
        stat_card("Keywords totais",   fmt_int(s$kw_total)),
        stat_card("Já processadas",    fmt_int(s$kw_done),
                  sub = paste0(s$kw_pending, " pendentes"), color = "#065f46"),
        stat_card("Artigos no projeto", fmt_int(s$n_articles)),
        stat_card("Com fulltext",       paste0(fmt_int(s$n_ft), " (", pct_ft, "%)"),
                  color = "#92400e")
      ),
      h5("Histórico de rodadas"),
      runs_table
    )
  })

  # ---------------------------------------------------------------------------
  # Sub-aba: Keywords
  # ---------------------------------------------------------------------------
  current_keywords <- reactive({
    pid <- selected_project_id(); req(pid)
    keywords_refresh()
    db_op(\(con) project_keywords(con, pid))
  })

  output$subtab_keywords <- renderUI({
    tagList(
      div(style = "display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;",
        h5("Keywords do projeto", style = "margin:0;"),
        div(
          actionButton("btn_add_keyword", "+ Adicionar keyword",
                       class = "btn-primary btn-sm", icon = icon("plus")),
          actionButton("btn_del_keyword", "Remover selecionada",
                       class = "btn-outline-danger btn-sm",
                       icon = icon("trash"),
                       style = "margin-left: 8px;")
        )
      ),
      DT::DTOutput("keywords_table"),
      p(class = "footer-note",
        "Keywords com status ", em("pendente"),
        " serão processadas na próxima rodada. ",
        "Datas em branco usam as datas do projeto.")
    )
  })

  output$keywords_table <- DT::renderDT({
    df <- current_keywords()
    if (nrow(df) == 0) {
      return(DT::datatable(
        data.frame(Mensagem = "Nenhuma keyword. Adicione uma para começar."),
        options = list(dom = "t", paging = FALSE, info = FALSE, ordering = FALSE),
        rownames = FALSE
      ))
    }
    show <- data.frame(
      ID = df$id,
      Keyword = df$keyword,
      `Data ini.` = ifelse(is.na(df$date_start_override), "—", fmt_date_br(df$date_start_override)),
      `Data fim.` = ifelse(is.na(df$date_end_override),   "—", fmt_date_br(df$date_end_override)),
      Status = vapply(df$status, status_badge, character(1)),
      `Bruto` = fmt_int(df$n_search_raw),
      `Novos` = fmt_int(df$n_new_added),
      `Existiam` = fmt_int(df$n_existing_matched),
      Adicionada = format(as.POSIXct(df$added_at), "%d/%m %H:%M"),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    DT::datatable(
      show, selection = "single", escape = FALSE, rownames = FALSE,
      class = "compact stripe hover",
      options = list(
        dom = "ftip", pageLength = 15,
        language = list(search = "Filtrar:", paginate = list(`next`="→", previous="←"),
                        info = "_START_–_END_ de _TOTAL_",
                        emptyTable = "Nenhuma keyword."),
        columnDefs = list(list(className = "dt-right", targets = c(0, 5, 6, 7)))
      )
    )
  })

  # Modal: adicionar keyword
  observeEvent(input$btn_add_keyword, {
    showModal(modalDialog(
      title = "Adicionar keyword",
      ui_add_keyword_form(),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancelar"),
        actionButton("ak_submit", "Adicionar", class = "btn-primary")
      )
    ))
  })

  observeEvent(input$ak_submit, {
    pid <- selected_project_id(); req(pid)
    kw <- trimws(input$ak_keyword %||% "")
    if (!nzchar(kw)) {
      showNotification("Keyword vazia.", type = "error"); return()
    }
    ds <- input$ak_start; de <- input$ak_end
    ds <- if (is.null(ds) || is.na(ds)) NA else as.character(ds)
    de <- if (is.null(de) || is.na(de)) NA else as.character(de)
    status <- tryCatch(
      db_op(\(con) project_add_keyword(con, pid, kw,
                                        date_start_override = ds,
                                        date_end_override = de)),
      error = function(e) {
        showNotification(paste0("Erro: ", conditionMessage(e)), type = "error"); NULL
      }
    )
    if (is.null(status)) return()
    removeModal()
    if (status == "already_exists") {
      showNotification("Essa keyword já existe no projeto.", type = "warning")
    } else {
      showNotification(paste0("Keyword '", kw, "' adicionada."), type = "message")
      keywords_refresh(keywords_refresh() + 1L)
    }
  })

  observeEvent(input$btn_del_keyword, {
    sel <- input$keywords_table_rows_selected
    if (length(sel) == 0) {
      showNotification("Selecione uma keyword para remover.", type = "warning"); return()
    }
    kw_row <- current_keywords()[sel, ]
    if (kw_row$status %in% c("done", "searching")) {
      showNotification(
        "Esta keyword já foi processada. Remover apaga apenas a configuração; ",
        "os artigos coletados permanecem no projeto.", type = "warning")
    }
    showModal(modalDialog(
      title = "Confirmar remoção",
      p("Remover a keyword ", strong(kw_row$keyword), "?"),
      footer = tagList(
        modalButton("Cancelar"),
        actionButton("dk_confirm", "Remover", class = "btn-danger")
      )
    ))
  })

  observeEvent(input$dk_confirm, {
    sel <- input$keywords_table_rows_selected
    if (length(sel) == 0) { removeModal(); return() }
    kw_id <- current_keywords()$id[sel]
    db_op(\(con) DBI::dbExecute(con,
      "DELETE FROM project_keywords WHERE id = ?", params = list(kw_id)))
    removeModal()
    keywords_refresh(keywords_refresh() + 1L)
    showNotification("Keyword removida.", type = "message")
  })

  # ---------------------------------------------------------------------------
  # Sub-aba: Coleta
  # ---------------------------------------------------------------------------
  output$subtab_run <- renderUI({
    pid <- selected_project_id(); req(pid)
    kw <- current_keywords()
    pending <- sum(kw$status == "pending", na.rm = TRUE)
    proc <- run_proc()
    running <- !is.null(proc) && proc$is_alive()

    tagList(
      h5("Coletar artigos"),
      div(style = "margin-bottom:12px;",
        if (pending == 0 && !running) {
          div(class = "alert alert-info",
              "Nenhuma keyword pendente. Adicione uma na aba Keywords ",
              "ou marque keywords concluídas para reprocessar.")
        } else if (running) {
          div(class = "alert alert-warning",
              tags$strong("⏳ Coleta em andamento."),
              " Log atualiza a cada segundo. Mantenha o app aberto.")
        } else {
          div(class = "alert alert-light",
              fmt_int(pending), " keyword(s) pendente(s). ",
              "A coleta inclui busca, deduplicação e fulltext (sem LLM nesta versão).")
        }
      ),
      div(style = "margin-bottom:14px;",
        if (running) {
          actionButton("btn_stop", "■ Interromper", class = "btn-outline-danger")
        } else {
          actionButton("btn_run", "▶ Rodar coleta",
                       class = "btn-primary btn-lg",
                       disabled = (pending == 0))
        }
      ),
      h6("Log da rodada"),
      tags$pre(class = "run-log", textOutput("run_log", inline = TRUE)),
      p(class = "footer-note",
        "A coleta roda em processo separado. Você pode navegar para outras ",
        "abas — o log continua atualizando aqui quando você voltar.")
    )
  })

  observeEvent(input$btn_run, {
    pid <- selected_project_id(); req(pid)
    if (!is.null(run_proc()) && run_proc()$is_alive()) {
      showNotification("Coleta já em andamento.", type = "warning"); return()
    }
    log_path <- file.path(LOG_DIR,
                          paste0("run_", pid, "_",
                                 format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))
    file.create(log_path)

    proc <- tryCatch(
      callr::r_bg(
        func = function(repo_root, project_id) {
          setwd(repo_root)
          for (f in c("db.R","utils.R","scrape.R","dedup.R",
                      "projects.R","llm.R","pipeline.R","export.R")) {
            source(file.path("R", f))
          }
          con <- db_connect()
          on.exit(db_close(con))
          run_collection(con, project_id, skip_llm = TRUE)
        },
        args   = list(repo_root = APP_ROOT, project_id = pid),
        stdout = log_path,
        stderr = "2>&1",
        supervise = TRUE
      ),
      error = function(e) {
        showNotification(paste0("Falha ao iniciar coleta: ", conditionMessage(e)),
                          type = "error")
        NULL
      }
    )
    if (is.null(proc)) return()
    run_proc(proc)
    run_log_file(log_path)
    run_finished_at(NULL)
    showNotification("Coleta iniciada.", type = "message", duration = 3)
  })

  observeEvent(input$btn_stop, {
    proc <- run_proc()
    if (!is.null(proc) && proc$is_alive()) {
      tryCatch(proc$kill(), error = function(e) NULL)
      showNotification("Coleta interrompida.", type = "warning")
    }
  })

  # Live log via reactivePoll
  run_log_text <- reactivePoll(
    intervalMillis = 1000,
    session        = session,
    checkFunc      = function() {
      lf <- run_log_file()
      if (is.null(lf) || !file.exists(lf)) return("0|0")
      proc <- run_proc()
      alive <- !is.null(proc) && proc$is_alive()
      paste(file.info(lf)$size, as.integer(alive), sep = "|")
    },
    valueFunc      = function() {
      lf <- run_log_file()
      if (is.null(lf) || !file.exists(lf)) {
        return("(sem rodada ainda — clique em ▶ Rodar coleta)")
      }
      ln <- tryCatch(readLines(lf, warn = FALSE, encoding = "UTF-8"),
                      error = function(e) character(0))
      if (length(ln) == 0) "(iniciando...)" else paste(ln, collapse = "\n")
    }
  )
  output$run_log <- renderText({ run_log_text() })

  # Detecta término do processo e refresca dados
  observe({
    invalidateLater(1500, session)
    proc <- run_proc()
    if (is.null(proc)) return()
    if (!proc$is_alive() && is.null(run_finished_at())) {
      run_finished_at(Sys.time())
      keywords_refresh(keywords_refresh() + 1L)
      corpus_refresh(corpus_refresh() + 1L)
      projects_refresh(projects_refresh() + 1L)
      exit <- tryCatch(proc$get_exit_status(), error = function(e) NA)
      if (!is.na(exit) && exit == 0) {
        showNotification("✓ Coleta concluída.", type = "default", duration = 6)
      } else {
        showNotification(paste0("Coleta terminou com status ", exit %||% "?"),
                          type = "warning", duration = 8)
      }
    }
  })

  # ---------------------------------------------------------------------------
  # Sub-aba: Corpus
  # ---------------------------------------------------------------------------
  corpus_df <- reactive({
    pid <- selected_project_id(); req(pid)
    corpus_refresh()
    db_op(\(con) project_corpus(con, pid))
  })

  output$subtab_corpus <- renderUI({
    df <- corpus_df()
    if (nrow(df) == 0) {
      return(div(class = "alert alert-info",
                 "Nenhum artigo ainda. Adicione keywords e rode a coleta."))
    }
    eras <- sort(unique(stats::na.omit(df$era)))
    statuses <- sort(unique(df$fulltext_status))
    dates <- suppressWarnings(as.Date(df$date))
    dr_min <- if (all(is.na(dates))) Sys.Date() - 365 * 5 else min(dates, na.rm = TRUE)
    dr_max <- if (all(is.na(dates))) Sys.Date()           else max(dates, na.rm = TRUE)

    tagList(
      div(style = "display:flex;gap:12px;flex-wrap:wrap;margin-bottom:12px;align-items:flex-end;",
        div(style = "min-width:160px;",
            checkboxGroupInput("cf_era", "Era",
              choices = setNames(eras, paste0("Era ", eras)),
              selected = eras, inline = TRUE)),
        div(style = "min-width:200px;",
            checkboxGroupInput("cf_status", "Fulltext",
              choices = statuses, selected = statuses, inline = TRUE)),
        div(style = "min-width:240px;",
            dateRangeInput("cf_date", "Período",
              start = dr_min, end = dr_max,
              format = "dd/mm/yyyy", language = "pt-BR", separator = " → ")),
        div(style = "flex:1; min-width:200px;",
            textInput("cf_search", "Buscar no título / fulltext",
                      placeholder = "ex.: cota racial"))
      ),
      uiOutput("corpus_count_summary"),
      DT::DTOutput("corpus_table")
    )
  })

  corpus_filtered <- reactive({
    df <- corpus_df()
    if (is.null(df) || nrow(df) == 0) return(df)
    out <- df
    if (!is.null(input$cf_era) && length(input$cf_era) > 0) {
      out <- out[is.na(out$era) | out$era %in% as.integer(input$cf_era), ]
    }
    if (!is.null(input$cf_status) && length(input$cf_status) > 0) {
      out <- out[out$fulltext_status %in% input$cf_status, ]
    }
    if (!is.null(input$cf_date)) {
      d <- suppressWarnings(as.Date(out$date))
      keep <- is.na(d) | (d >= input$cf_date[1] & d <= input$cf_date[2])
      out <- out[keep, ]
    }
    if (!is.null(input$cf_search) && nzchar(input$cf_search)) {
      q <- tolower(input$cf_search)
      m_title <- grepl(q, tolower(out$title %||% ""), fixed = TRUE)
      m_ft    <- grepl(q, tolower(out$full_text %||% ""), fixed = TRUE)
      out <- out[m_title | m_ft, ]
    }
    out
  })

  output$corpus_count_summary <- renderUI({
    total <- nrow(corpus_df())
    fltd  <- nrow(corpus_filtered())
    p(style = "color:#6b7280;font-size:13px;",
      "Exibindo ", strong(fmt_int(fltd)), " de ", strong(fmt_int(total)), " artigos.")
  })

  output$corpus_table <- DT::renderDT({
    df <- corpus_filtered()
    if (nrow(df) == 0) {
      return(DT::datatable(data.frame(Mensagem = "Nenhum artigo com esses filtros."),
                        options = list(dom="t"), rownames = FALSE))
    }
    show <- data.frame(
      Data = fmt_date_br(df$date),
      Era  = df$era,
      Status = vapply(df$fulltext_status, status_badge, character(1)),
      Título = ifelse(nchar(df$title %||% "") > 80,
                      paste0(substr(df$title, 1, 78), "…"),
                      df$title),
      Seção = df$section %||% "",
      `Match keywords` = df$matched_keywords,
      `Fulltext (chars)` = ifelse(is.na(df$full_text), 0L, nchar(df$full_text)),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    DT::datatable(
      show, selection = "single", escape = FALSE, rownames = FALSE,
      class = "compact stripe hover",
      options = list(
        dom = "ftip", pageLength = 25,
        language = list(search = "Filtrar tabela:",
                        paginate = list(`next`="→", previous="←"),
                        info = "_START_–_END_ de _TOTAL_",
                        emptyTable = "Sem dados."),
        columnDefs = list(list(className = "dt-right", targets = c(1, 6)))
      )
    )
  })

  observeEvent(input$corpus_table_rows_selected, {
    sel <- input$corpus_table_rows_selected
    if (length(sel) == 0) return()
    row <- corpus_filtered()[sel, ]
    showModal(modalDialog(
      title = row$title %||% "(sem título)",
      size  = "l",
      easyClose = TRUE,
      tagList(
        div(style = "color:#6b7280;font-size:13px;margin-bottom:10px;",
            fmt_date_br(row$date), " · Era ", row$era %||% "?",
            " · ", HTML(status_badge(row$fulltext_status)),
            if (nzchar(row$section %||% "")) tagList(" · ", row$section)
        ),
        if (nzchar(row$matched_keywords %||% ""))
          div(style = "margin-bottom:8px;",
              tags$small(tags$strong("Keywords: "),
                         row$matched_keywords)),
        if (nzchar(row$excerpt %||% ""))
          div(style = "background:#fef9c3;padding:10px;border-radius:6px;margin-bottom:10px;font-style:italic;",
              row$excerpt),
        if (!is.na(row$full_text) && nchar(row$full_text) > 0) {
          tagList(
            h6("Texto completo"),
            tags$div(class = "article-fulltext", row$full_text)
          )
        } else {
          div(class = "alert alert-warning",
              "Fulltext não disponível (status: ", row$fulltext_status, ").")
        },
        div(style = "margin-top:14px;",
            tags$a(href = row$url, target = "_blank",
                   "↗ Abrir na Folha"))
      ),
      footer = modalButton("Fechar")
    ))
  })

  # ===========================================================================
  # CLEANUP
  # ===========================================================================
  session$onSessionEnded(function() {
    proc <- isolate(run_proc())
    if (!is.null(proc) && proc$is_alive()) {
      try(proc$kill(), silent = TRUE)
    }
  })
}

# -----------------------------------------------------------------------------
shinyApp(ui, server)
