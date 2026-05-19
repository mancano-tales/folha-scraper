# CLAUDE.md — folha-scraper

Contexto para assistentes de IA. Para o usuário, ver [README.md](README.md).

---

## Origem

Spinoff de `Mancano2026-MA-Thesis/4-DA-Code/2026-05_Folha_Scraper`. A versão da tese é monolítica, single-project, persiste em CSV. Esta versão é multi-projeto, persiste em SQLite, e é o lar de desenvolvimento contínuo. **Não modificar a pasta da tese** — fica congelada como artefato.

A história e os bugs resolvidos na origem estão documentados em [`Mancano2026-MA-Thesis/4-DA-Code/2026-05_Folha_Scraper/DIARIO-AGENTE.md`](../Mancano2026-MA-Thesis/4-DA-Code/2026-05_Folha_Scraper/DIARIO-AGENTE.md). Leia esse arquivo antes de mexer nos parsers HTML — os 8 bugs estruturais ali documentados continuam aplicáveis aqui.

---

## Arquitetura

**Camada de biblioteca** (`R/`), totalmente funcional sem UI:

| Arquivo | Responsabilidade |
|---|---|
| `db.R` | Conexão SQLite, migrations versionadas, CRUD genérico |
| `utils.R` | Logging, HTTP com retry/delay, normalização de strings, parsing de datas pt-BR |
| `scrape.R` | Busca paginada (`search_keyword`) + parsing de fulltext (`fetch_fulltext`); cobre 3 eras de layout da Folha |
| `dedup.R` | Fuzzy dedup por título (Jaro-Winkler, threshold configurável) |
| `projects.R` | CRUD de projetos, keywords e classificações |
| `llm.R` | Classificação via DeepSeek; few-shot por projeto |
| `pipeline.R` | Orquestrador: `run_collection(db, project_id)` |

**Camada de entrypoints** (`scripts/`):

- `cli.R` — dispatcher para uso via `Rscript` (new-project, add-keyword, run, refresh-fulltext, etc.)
- `import_thesis_corpus.R` — migra CSV da tese → SQLite
- `run_app.R` — lança o Shiny app

**Camada de UI** (`app/`):

- `global.R` — bootstrap; resolve `APP_ROOT`, sourcia `R/*.R`, abre conexão padrão do DB
- `app.R` — UI + server num arquivo (~700 linhas, padrão educabr). 3 navs: Projetos, Projeto atual, Sobre. Sub-navs no projeto atual: Visão geral, Keywords, Coleta, Corpus
- **v0.2 não expõe features LLM no app**: classificação e few-shot existem na biblioteca mas a UI usa `skip_llm = TRUE` por padrão. Plano em v0.2.x

**Schema** em `migrations/0001_init.sql`. Versões futuras: `0002_*.sql`, etc.

**Camada de documentação** (`website/` + `docs/`):

- `website/_quarto.yml` — config do site Quarto: navbar, tema (`cosmo` + SCSS custom em `#1a3a5c`), footer, formato HTML
- `website/index.qmd`, `comecar.qmd`, `referencia.qmd`, `sobre.qmd` — 4 páginas
- `docs/` — output do `quarto render` (commitado, servido via GitHub Pages a partir de `/docs` na branch main)
- Rebuild: `cd website && quarto render`

---

## NÃO é um pacote R

Apesar do layout (`R/` na raiz, comentários estilo roxygen), este repositório **não é um pacote R instalável**. Não tem `DESCRIPTION`, `NAMESPACE`, `man/` nem `inst/`. Modelo de uso é **clone-and-run**:

- Usuário clona o repo, abre R na raiz, roda `source("R/run_app.R"); run_app()`
- Banco SQLite vive em `data/folha.sqlite` **dentro do clone** (não em `tools::R_user_dir`)
- Comentários `#'` em `R/*.R` são docstrings inline para IDEs (RStudio mostra na completion); **não geram `man/`**

Por que essa escolha: ver `website/sobre.qmd` seção "Por que clone-and-run". Resumo: estado é por-usuário (cada clone tem seu banco), iteração rápida importa, e o autor já vive em Quarto. Se um dia precisar virar pacote (alguém querer `library(folhascraper)` em script próprio), a conversão é simples — re-criar `DESCRIPTION`/`NAMESPACE`, mover `migrations/` para `inst/migrations/`, ajustar `db_path_default()` para `tools::R_user_dir()`.

---

## Invariantes críticas

**1. URL como identidade do artigo.** A tabela `articles` é URL-keyed (`url_clean` PK). Mesmo artigo coletado em projetos diferentes existe uma única vez. Qualquer query que precise "qual artigo é este" usa `url_clean`, não título nem ID.

**2. Coleta de fulltext é compartilhada; classificação é por-projeto.** Se article já tem `full_text`, projetos novos reutilizam. `classifications` tem chave composta `(project_id, url_clean)` — mesmo artigo pode ter relevância "sim" num projeto e "não" em outro.

**3. Keyword é tag, não filtro.** `project_articles.matched_keywords` é uma string separada por `;` listando quais keywords do projeto encontraram o artigo. Re-rodar uma keyword apenas estende essa string, nunca duplica artigos.

**4. Datas por keyword sobrescrevem datas do projeto.** `project_keywords.date_start_override` / `date_end_override` são opcionais. Se nulos, fallback para `projects.date_start` / `date_end`. Casos de uso: "Lei de Cotas" só faz sentido a partir de 2012, embora o projeto cubra 2003-2020.

**5. Persistência usa SQLite via DBI.** Nunca usar `read.csv`/`write.csv` para dados do pipeline — texto longo com `\n` quebra silenciosamente. CSVs só são lidos no script de importação legacy.

---

## Parsers HTML da Folha — pontos sensíveis

Mesmas três eras documentadas na origem:

- **Era 1 (1994–2003)**: layout em tabela, texto com `<br>`, sem `<time>`. Data extraída via regex da URL (`/fsp/YYYY/M/D/`).
- **Era 2 (2003–2015)**: `div.article` com `<p>` ou texto solto. URLs estilo `fcDDMMYYYY.htm`.
- **Era 3 (2015+)**: `div.c-news__body`, `<time datetime="DD.mmm.YYYY às HHhMM">`.

Seletores em cascata. Se a Folha redesenhar o site, rodar `inspect_search_page()` / `inspect_article_page()` em URLs de cada era antes de assumir que tudo está bem.

**Não readicionar `&site=folha` à URL de busca.** Causa erro fatal silencioso (Bug 1 do diário).

---

## Convenções

- Nomes de função em snake_case, prefixados por domínio: `project_create`, `db_connect`, `search_keyword`.
- Tudo que conversa com o banco recebe `db` (conexão DBI) como primeiro argumento.
- Datas internas em formato ISO `YYYY-MM-DD`. Datas para a Folha em `DD/MM/YYYY` (a API exige).
- Tempos em ISO 8601 com fuso, via `format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")`.
- Erros não-fatais (uma keyword que falha, um artigo sem fulltext) viram linha em `runs` ou coluna `error_msg`, **não** `stop()`. Erros fatais (DB inacessível, API key inválida com `SKIP_LLM = FALSE`) são `stop()`.

---

## Padrões do Shiny app

- **Conexões DB de curta duração.** Cada handler usa `db_op(\(con) ...)` que abre, executa e fecha. Evita locks longos no SQLite. Migrations são idempotentes (versionadas em `schema_version`), então re-abrir é barato.
- **Refresh reativo via contadores.** `projects_refresh`, `keywords_refresh`, `corpus_refresh` são `reactiveVal(0L)` que incrementam após mutações. Reactives que dependem deles re-disparam.
- **Coleta em background via `callr::r_bg()`.** Processo filho re-sourcia `R/*.R` e roda `run_collection()`. Stdout/stderr redirecionados para arquivo em `tempdir()`. UI lê com `reactivePoll(1000)` e renderiza num `<pre>` estilizado tipo terminal.
- **Detecção de término.** `observe()` com `invalidateLater(1500)` checa `proc$is_alive()`. Quando vira FALSE, dispara um refresh global dos contadores e notifica o usuário (uma única vez via flag `run_finished_at`).
- **Modais para forms.** Novo projeto, adicionar keyword, ver artigo: todos usam `showModal(modalDialog(...))`. Submit faz `removeModal()` no sucesso.

## O que NÃO está implementado

- **Sem exportação Excel ainda.** Função `export_excel_project(db, id, file)` existe como stub em `R/export.R`. `project_corpus(con, id)` já retorna o tibble do corpus — falta só montar o workbook multi-aba.
- **Sem features LLM no app.** Biblioteca tem zero-shot e few-shot via DeepSeek (`R/llm.R`), mas a UI v0.2 não expõe. Plano em v0.2.1.
- **Sem auditoria LLM no app** (planejado para v0.4).
- **Apenas DeepSeek.** Estrutura permite trocar provedor (`R/llm.R` tem `call_llm()` com provider arg), mas só DeepSeek implementado.
- **Apenas Folha.** Outras fontes exigiriam novos parsers; arquitetura não generaliza sem refactor.

---

## Ao trabalhar aqui

- Manter as invariantes (seção acima).
- Schema novo? Criar `migrations/000N_descrição.sql`. `db_migrate()` aplica em ordem automaticamente. Nunca editar migrations antigas em produção.
- Antes de mexer em parsers, validar com `inspect_*` em URLs de cada era.
- Testes vão para `tests/testthat/` (placeholder por enquanto; bom alvo: snapshot HTML por era).
- Mexeu na documentação? Rodar `cd website && quarto render` para regenerar `docs/`, commitar `docs/` junto. Não rodamos GH Action ainda — é build local + commit.
- **Não recriar `DESCRIPTION` / `NAMESPACE` / `inst/`** sem discussão explícita com o usuário. A decisão de não ser pacote foi tomada conscientemente (ver `website/sobre.qmd`).
