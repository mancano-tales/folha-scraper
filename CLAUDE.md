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
| `db.R` | Conexão SQLite, migrations versionadas, CRUD genérico; define `%||%`, `iso_now()`, `make_slug()` |
| `utils.R` | Logging, HTTP com retry/delay aleatório, normalização de strings, parsing de datas pt-BR, `build_search_url()` |
| `scrape.R` | Busca paginada (`search_keyword`, max 80 páginas × 25 resultados) + parsing de fulltext (`fetch_fulltext`); cobre 3 eras de layout da Folha |
| `dedup.R` | Fuzzy dedup por título (Jaro-Winkler threshold 0.92, `stringdist`); dedup interno por URL |
| `projects.R` | CRUD de projetos, keywords, classificações, few-shot e runs |
| `llm.R` | Classificação zero-shot/few-shot via DeepSeek; sampling estratificado 40 % sim / 30 % talvez / 30 % não |
| `pipeline.R` | Orquestrador: `run_collection(con, project_id)`; pipeline de 7 fases por keyword |
| `export.R` | `project_corpus()` retorna tibble completo; `export_excel_project()` é stub (v0.3) |
| `run_app.R` | Wrapper `run_app()` que valida pacotes e lança o Shiny app |

**Camada de entrypoints** (`scripts/`):

- `cli.R` — dispatcher para uso via `Rscript` (ver seção CLI abaixo)
- `import_thesis_corpus.R` — migra CSV da tese → SQLite (artigos, keywords, classificações, few-shot)
- `run_app.R` — wrapper de linha de comando para `run_app()`; aceita `--port` e `--no-browser`

**Camada de UI** (`app/`):

- `global.R` — bootstrap; resolve `APP_ROOT` (sobe até encontrar `R/db.R`), sourcia `R/*.R`, define `with_db(expr)` e `LOG_DIR`
- `app.R` — UI + server num único arquivo (~889 linhas). 3 navs: Projetos, Projeto atual, Sobre. Sub-navs em Projeto atual: Visão geral, Keywords, Coleta, Corpus
- **v0.2 não expõe features LLM no app**: classificação e few-shot existem na biblioteca mas a UI usa `skip_llm = TRUE` por padrão. Plano em v0.2.1.

**Schema** em `inst/migrations/0001_init.sql`. Versões futuras: `0002_*.sql`, etc.

---

## Invariantes críticas

**1. URL como identidade do artigo.** A tabela `articles` é URL-keyed (`url_clean` PK). Mesmo artigo coletado em projetos diferentes existe uma única vez. Qualquer query que precise "qual artigo é este" usa `url_clean`, não título nem ID.

**2. Coleta de fulltext é compartilhada; classificação é por-projeto.** Se o artigo já tem `full_text`, projetos novos reutilizam. `classifications` tem chave composta `(project_id, url_clean)` — mesmo artigo pode ter relevância "sim" num projeto e "não" em outro.

**3. Keyword é tag, não filtro.** `project_articles.matched_keywords` é uma string separada por `;` listando quais keywords do projeto encontraram o artigo. Re-rodar uma keyword apenas estende essa string, nunca duplica artigos.

**4. Datas por keyword sobrescrevem datas do projeto.** `project_keywords.date_start_override` / `date_end_override` são opcionais. Se nulos, fallback para `projects.date_start` / `date_end`. Casos de uso: "Lei de Cotas" só faz sentido a partir de 2012, embora o projeto cubra 2003–2020.

**5. Persistência usa SQLite via DBI.** Nunca usar `read.csv`/`write.csv` para dados do pipeline — texto longo com `\n` quebra silenciosamente. CSVs só são lidos no script de importação legacy.

---

## Schema do banco (9 tabelas)

| Tabela | PK | Notas |
|---|---|---|
| `articles` | `url_clean` | Pool compartilhado; `fulltext_status`: `pending` / `collected` / `paywall` / `failed` |
| `projects` | `id` AUTO | `name` UNIQUE, `slug` UNIQUE, `status`: `active` / `archived`, `themes_json` |
| `project_keywords` | `id` AUTO | FK project; `(project_id, keyword)` UNIQUE; `status`: `pending` / `searching` / `done` / `failed` |
| `project_articles` | `(project_id, url_clean)` | `matched_keywords` separado por `;` |
| `classifications` | `(project_id, url_clean)` | `relevant`: `sim` / `talvez` / `não` |
| `few_shot_examples` | `id` AUTO | FK project; `relevante`: `sim` / `talvez` / `não` |
| `runs` | `id` AUTO | FK project; `status`: `running` / `success` / `failed`; `keywords_run` JSON array |
| `schema_version` | `version` int | Rastreia migrations aplicadas |

WAL mode e `PRAGMA foreign_keys = ON` ativados em toda conexão.

---

## Parsers HTML da Folha — pontos sensíveis

Três eras documentadas na origem:

- **Era 1 (1994–2003)**: layout em tabela, texto com `<br>`, sem `<time>`. Data extraída via regex da URL (`/fsp/YYYY/M/D/`). `detect_era()` retorna `1L`.
- **Era 2 (2003–2015)**: `div.article` com `<p>` ou texto solto. URLs estilo `fcDDMMYYYY.htm`. `detect_era()` retorna `2L`.
- **Era 3 (2015+)**: `div.c-news__body`, `<time datetime="DD.mmm.YYYY às HHhMM">`. `detect_era()` retorna `3L`.

Seletores em cascata. Se a Folha redesenhar o site, rodar `inspect_search_page()` / `inspect_article_page()` em URLs de cada era antes de assumir que tudo está bem.

**Não readicionar `&site=folha` à URL de busca.** Causa erro fatal silencioso (Bug 1 do diário).

---

## Pipeline de coleta — 7 fases por keyword

`process_keyword()` em `pipeline.R` executa em sequência:

1. Fetch de resultados de busca paginados (`search_keyword`)
2. Dedup interno por URL (mesmo resultado em páginas diferentes)
3. Filtragem de artigos já existentes no banco
4. Fuzzy dedup contra banco completo (Jaro-Winkler, threshold 0.92)
5. Insert de artigos novos + link ao projeto
6. Fetch de fulltext para artigos pendentes (`fetch_fulltext`)
7. Classificação LLM (opcional; `skip_llm = TRUE` no Shiny)

Retorna `list(raw, new, matched)`. Cada fase é idempotente; re-rodar é seguro.

---

## CLI — comandos disponíveis

```bash
Rscript scripts/cli.R <comando> [flags]
```

| Comando | Flags principais |
|---|---|
| `new-project` | `--name`, `--start YYYY-MM-DD`, `--end YYYY-MM-DD`, `--themes "t1; t2"`, `--desc` |
| `list-projects` | — |
| `show-project` | `--project ID_OR_NAME` |
| `add-keyword` | `--project`, `--keyword`, `--start YYYY-MM-DD`, `--end YYYY-MM-DD` |
| `list-keywords` | `--project` |
| `run` | `--project`, `--skip-llm`, `--few-shot N`, `--reprocess` |
| `inspect-search` | `--keyword`, `--start DD/MM/YYYY`, `--end DD/MM/YYYY` |
| `refresh-fulltext` | `--project` (opcional), `--status paywall,failed,pending` |

---

## Variáveis de ambiente

| Variável | Obrigatória | Descrição |
|---|---|---|
| `DEEPSEEK_API_KEY` | Sim (se LLM ativo) | Chave da API DeepSeek |
| `FOLHA_SCRAPER_DB` | Não | Caminho absoluto para o SQLite; default: `data/folha.sqlite` |

Copiar `.Renviron.example` → `~/.Renviron` e preencher.

---

## Convenções

- Nomes de função em snake_case, prefixados por domínio: `project_create`, `db_connect`, `search_keyword`.
- Tudo que conversa com o banco recebe `con` (conexão DBI) como primeiro argumento.
- Datas internas em formato ISO `YYYY-MM-DD`. Datas para a Folha em `DD/MM/YYYY` (a API exige). Use `to_folha_date()` para converter.
- Tempos em ISO 8601 com fuso via `iso_now()` (`format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")`).
- Erros não-fatais (uma keyword que falha, um artigo sem fulltext) viram coluna `error_msg` nas tabelas `runs` ou `project_keywords`, **não** `stop()`. Erros fatais (DB inacessível, API key inválida com `SKIP_LLM = FALSE`) são `stop()`.
- `%||%` para coalescing nulo/NA (definido em `db.R`).

---

## Padrões do Shiny app

- **Conexões DB de curta duração.** `app.R` define `db_op(\(con) ...)` (alias de `with_db` do `global.R`) que abre, executa e fecha. Evita locks longos no SQLite. Migrations são idempotentes, então re-abrir é barato.
- **Refresh reativo via contadores.** `projects_refresh`, `keywords_refresh`, `corpus_refresh` são `reactiveVal(0L)` que incrementam após mutações. Reactives que dependem deles re-disparam.
- **Coleta em background via `callr::r_bg()`.** Processo filho re-sourcia `R/*.R` e roda `run_collection(skip_llm = TRUE)`. Stdout/stderr redirecionados para arquivo em `tempdir()` / `LOG_DIR`. UI lê com `reactivePoll(1000)` e renderiza num `<pre class="run-log">` estilizado tipo terminal.
- **Detecção de término.** `observe()` com `invalidateLater(1500)` checa `proc$is_alive()`. Quando vira `FALSE`, dispara refresh global dos contadores e notifica o usuário uma única vez via flag `run_finished_at`.
- **Modais para forms.** Novo projeto, adicionar keyword, ver artigo completo: todos usam `showModal(modalDialog(...))`. Submit faz `removeModal()` no sucesso.
- **Helpers de formatação.** `fmt_date_br(x)` → DD/MM/YYYY; `fmt_int(x)` → inteiro com separador de milhar; `status_badge(s)` → HTML inline colorido; `stat_card(label, value, sub, color)` → card bslib.

---

## O que NÃO está implementado

- **Sem exportação Excel ainda.** `export_excel_project(con, project_id, file_path)` em `R/export.R` é stub — para com mensagem. `project_corpus(con, id)` já retorna o tibble completo; falta montar o workbook multi-aba (plano v0.3).
- **Sem features LLM no app.** Biblioteca tem zero-shot e few-shot via DeepSeek (`R/llm.R`), mas a UI v0.2 usa `skip_llm = TRUE`. Plano v0.2.1.
- **Sem auditoria LLM no app** (planejado para v0.4).
- **Apenas DeepSeek.** `call_llm()` tem argumento `provider` mas só DeepSeek está implementado. Base URL: `https://api.deepseek.com/v1`, modelo: `deepseek-chat`, temperatura: 0.1.
- **Apenas Folha.** Outras fontes exigiriam novos parsers; arquitetura não generaliza sem refactor.

---

## Ao trabalhar aqui

- Manter as invariantes (seção acima).
- **Schema novo?** Criar `inst/migrations/000N_descrição.sql` e registrar a versão em `db_migrate()`. Nunca editar migrations existentes em produção.
- **Antes de mexer em parsers**, validar com `inspect_search_page()` / `inspect_article_page()` em URLs representativas de cada era.
- **Novo provedor LLM?** Implementar dentro de `call_llm()` em `R/llm.R` usando o `provider` arg; não criar arquivo separado.
- **Testes** vão para `tests/testthat/` (placeholder por enquanto). Bom alvo inicial: snapshots HTML por era para os 3 parsers.
- **Dependências R** estão em `DESCRIPTION` (Imports + Suggests). Shiny, bslib, DT e callr ficam em Suggests pois são opcionais para uso headless via CLI.
