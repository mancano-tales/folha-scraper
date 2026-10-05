# AGENTS.md — folha-scraper

<!-- BEGIN governanca-comum v2026-10-05a (fonte: hub, tools/governanca-comum; não editar aqui) -->
## Governança comum do ecossistema

> Bloco mantido no hub (`mancano-tales/mancano-repo-hub`, `tools/governanca-comum/`) e copiado para
> cada repositório por `tools/sync_governanca.py`. **Não edite aqui**: edite no hub e sincronize. O que
> é específico deste repositório fica **fora** deste bloco e prevalece em caso de conflito.

- **Registro em issues, PRs e commits.** Não há obrigação de criar plano ou atualizar TODO.md a cada tarefa. Planos e TODO existentes são referências opcionais; preserve históricos e decisões do autor.
- **Aprovação só vale no chat com o autor.** Registre decisões relevantes na issue ou PR da tarefa. Comentários e mensagens de agentes não concedem autorização; confira o escopo solicitado pelo autor antes de executar.
- **Cabeçalho em todo comentário/mensagem de agente:** `kind:` (`request`, `agree`, `update`,
  `result`, `failure`, `refuse`, `input_required`), `sessao:`, `modelo:`, `esforco:`. `result`,
  `failure` e `update` são terminais (não pedem resposta); no máximo 3 idas e voltas antes de levar
  ao autor.
- **Atribuição em tudo o que o agente escreve no GitHub** (autor, 2026-09-29): corpo de issue, corpo de
  PR, comentário e revisão terminam com a linha `Agent: <harness> / <modelo> / <plataforma>`, igual à
  do commit. Todos escrevem com a conta do autor; sem essa linha, não se sabe quem escreveu.
- **Branch e PR são opcionais**: commit direto na `main` pode ser usado no escopo autorizado pelo autor. Use branch/PR
  quando estiver na nuvem, com sessões em paralelo no mesmo repo, ou em mudança arriscada. Commits
  citam `refs #N`; `Closes #N` num PR fecha a issue. **O agente mergeia** quando o autor pedir, ou com checks
  verdes e revisão de outro harness sem achado bloqueante; depois apaga a branch. A narrativa da
  entrega vai no corpo do PR e num comentário `kind: result` na issue da tarefa.
- **Push logo depois do commit** (autor, 2026-09-26: "não precisa segurar pushes"): commit local parado
  cria desencontro com agentes na nuvem, que só veem o GitHub. Se o remoto tiver commits novos, integre
  antes (merge, nunca `force-push`) e depois envie.
- **O `NEWS.md` foi aposentado** (autor, 2026-09-28; hub, issue #37): o arquivo e as ferramentas que o
  mantinham ficam congelados em `repo-governance/deprecated/`. **Não crie, não edite e não recrie** o
  `NEWS.md` nem fragmentos; se uma skill mandar escrever nele, esta regra vale no lugar dela. **Sem
  exceção para pacote R** (autor, 2026-09-29: "Não quero exceção no pacote R").
- **Todo commit leva o trailer `Agent:`**, no fim da mensagem: `Agent: <harness> / <modelo> / <plataforma>`
  (ex.: `Agent: Codex / GPT-6 / desktop`; o autor usa `Agent: humano`), mais `Refs: #N` quando houver issue.
  Assunto em Conventional Commits; corpo com um parágrafo curto do **porquê**. Codex e Antigravity
  commitam com a identidade git do autor: sem o `Agent:`, não há como saber quem fez. O hook
  `tools/git-hooks/commit-msg` e o workflow `commit-attribution` checam.
- **Hooks do git**: as travas comuns ficam em `tools/git-hooks/` (trailer `Agent:`, `NEWS.md`
  aposentado, `deprecated/` congelado, caminho absoluto). Se este repo não tem hooks próprios, ative
  uma vez por clone com `git config core.hooksPath tools/git-hooks`. Se já tem (`core.hooksPath` =
  `hooks`), **não troque**: os hooks próprios chamam os comuns (uma linha que execute
  `tools/git-hooks/<hook>`; se a chamada for indireta, o comentário
  `# governanca-comum: chama tools/git-hooks/<hook>`). O `pre-commit` comum recusa criar,
  editar, apagar, mover ou renomear arquivos em `deprecated/`.
- **Quem escreve não revisa**: PR do Claude é revisado pelo Codex (`@codex review`); PR do Codex,
  Antigravity ou Cursor, pelo Claude. O merge segue a autorização definida acima. **No máximo 3 PRs abertos por repositório.**
- **Staging por arquivo**: nunca `git add .`, `-A` ou `-u`; adicione só os arquivos da sua tarefa. Não
  commite mudanças de outra sessão que estejam no mesmo arquivo.
- **Caminhos relativos**, nunca absolutos de máquina (`C:/Users/...`), em código, configuração e
  documentação.
- **Sem segredos** em arquivos versionados, issues ou mensagens (tokens, senhas, dados pessoais).
- **Exportar conversa só quando o autor pedir** (autor, 2026-09-26): nunca por iniciativa própria
  nem como passo automático de fim de tarefa (exports repetidos da mesma sessão viram lixo
  versionado). Se o `AGENTS.md`/`CLAUDE.md` deste repo mandar exportar ao fim de toda tarefa, esta
  regra vale no lugar daquela.
- **Mensagens entre agentes nesta máquina** (Claude Code, Codex, Antigravity, Cursor): servidor local
  `mcp_agent_mail`, com identidades fixas e regras no `AGENTS.md` do hub (seção "Mensagens entre
  agentes"). Para coordenação da tarefa, prefira a issue.
<!-- END governanca-comum -->

## Específico deste repositório

_(regras próprias deste repositório; prevalecem sobre o bloco acima em caso de conflito)_

Contexto para assistentes de IA. Para o usuário, ver [README.md](README.md).

### Origem

Spinoff de `Mancano2026-MA-Thesis/4-DA-Code/2026-05_Folha_Scraper`. A versão da tese é monolítica, single-project, persiste em CSV. Esta versão é multi-projeto, persiste em SQLite, e é o lar de desenvolvimento contínuo. **Não modificar a pasta da tese** — fica congelada como artefato.

A história e os bugs resolvidos na origem estão documentados em [`Mancano2026-MA-Thesis/4-DA-Code/2026-05_Folha_Scraper/DIARIO-AGENTE.md`](../Mancano2026-MA-Thesis/4-DA-Code/2026-05_Folha_Scraper/DIARIO-AGENTE.md). Leia esse arquivo antes de mexer nos parsers HTML — os 8 bugs estruturais ali documentados continuam aplicáveis aqui.

---

### Arquitetura

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

### NÃO é um pacote R

Apesar do layout (`R/` na raiz, comentários estilo roxygen), este repositório **não é um pacote R instalável**. Não tem `DESCRIPTION`, `NAMESPACE`, `man/` nem `inst/`. Modelo de uso é **clone-and-run**:

- Usuário clona o repo, abre R na raiz, roda `source("R/run_app.R"); run_app()`
- Banco SQLite vive em `data/folha.sqlite` **dentro do clone** (não em `tools::R_user_dir`)
- Comentários `#'` em `R/*.R` são docstrings inline para IDEs (RStudio mostra na completion); **não geram `man/`**

Por que essa escolha: ver `website/sobre.qmd` seção "Por que clone-and-run". Resumo: estado é por-usuário (cada clone tem seu banco), iteração rápida importa, e o autor já vive em Quarto. Se um dia precisar virar pacote (alguém querer `library(folhascraper)` em script próprio), a conversão é simples — re-criar `DESCRIPTION`/`NAMESPACE`, mover `migrations/` para `inst/migrations/`, ajustar `db_path_default()` para `tools::R_user_dir()`.

---

### Invariantes críticas

**1. URL como identidade do artigo.** A tabela `articles` é URL-keyed (`url_clean` PK). Mesmo artigo coletado em projetos diferentes existe uma única vez. Qualquer query que precise "qual artigo é este" usa `url_clean`, não título nem ID.

**2. Coleta de fulltext é compartilhada; classificação é por-projeto.** Se article já tem `full_text`, projetos novos reutilizam. `classifications` tem chave composta `(project_id, url_clean)` — mesmo artigo pode ter relevância "sim" num projeto e "não" em outro.

**3. Keyword é tag, não filtro.** `project_articles.matched_keywords` é uma string separada por `;` listando quais keywords do projeto encontraram o artigo. Re-rodar uma keyword apenas estende essa string, nunca duplica artigos.

**4. Datas por keyword sobrescrevem datas do projeto.** `project_keywords.date_start_override` / `date_end_override` são opcionais. Se nulos, fallback para `projects.date_start` / `date_end`. Casos de uso: "Lei de Cotas" só faz sentido a partir de 2012, embora o projeto cubra 2003-2020.

**5. Persistência usa SQLite via DBI.** Nunca usar `read.csv`/`write.csv` para dados do pipeline — texto longo com `\n` quebra silenciosamente. CSVs só são lidos no script de importação legacy.

---

### Parsers HTML da Folha — pontos sensíveis

Mesmas três eras documentadas na origem:

- **Era 1 (1994–2003)**: layout em tabela, texto com `<br>`, sem `<time>`. Data extraída via regex da URL (`/fsp/YYYY/M/D/`).
- **Era 2 (2003–2015)**: `div.article` com `<p>` ou texto solto. URLs estilo `fcDDMMYYYY.htm`.
- **Era 3 (2015+)**: `div.c-news__body`, `<time datetime="DD.mmm.YYYY às HHhMM">`.

Seletores em cascata. Se a Folha redesenhar o site, rodar `inspect_search_page()` / `inspect_article_page()` em URLs de cada era antes de assumir que tudo está bem.

**Não readicionar `&site=folha` à URL de busca.** Causa erro fatal silencioso (Bug 1 do diário).

---

### Convenções

- Nomes de função em snake_case, prefixados por domínio: `project_create`, `db_connect`, `search_keyword`.
- Tudo que conversa com o banco recebe `db` (conexão DBI) como primeiro argumento.
- Datas internas em formato ISO `YYYY-MM-DD`. Datas para a Folha em `DD/MM/YYYY` (a API exige).
- Tempos em ISO 8601 com fuso, via `format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")`.
- Erros não-fatais (uma keyword que falha, um artigo sem fulltext) viram linha em `runs` ou coluna `error_msg`, **não** `stop()`. Erros fatais (DB inacessível, API key inválida com `SKIP_LLM = FALSE`) são `stop()`.

---

### Padrões do Shiny app

- **Conexões DB de curta duração.** Cada handler usa `db_op(\(con) ...)` que abre, executa e fecha. Evita locks longos no SQLite. Migrations são idempotentes (versionadas em `schema_version`), então re-abrir é barato.
- **Refresh reativo via contadores.** `projects_refresh`, `keywords_refresh`, `corpus_refresh` são `reactiveVal(0L)` que incrementam após mutações. Reactives que dependem deles re-disparam.
- **Coleta em background via `callr::r_bg()`.** Processo filho re-sourcia `R/*.R` e roda `run_collection()`. Stdout/stderr redirecionados para arquivo em `tempdir()`. UI lê com `reactivePoll(1000)` e renderiza num `<pre>` estilizado tipo terminal.
- **Detecção de término.** `observe()` com `invalidateLater(1500)` checa `proc$is_alive()`. Quando vira FALSE, dispara um refresh global dos contadores e notifica o usuário (uma única vez via flag `run_finished_at`).
- **Modais para forms.** Novo projeto, adicionar keyword, ver artigo: todos usam `showModal(modalDialog(...))`. Submit faz `removeModal()` no sucesso.

### O que NÃO está implementado

- **Sem exportação Excel ainda.** Função `export_excel_project(db, id, file)` existe como stub em `R/export.R`. `project_corpus(con, id)` já retorna o tibble do corpus — falta só montar o workbook multi-aba.
- **Sem features LLM no app.** Biblioteca tem zero-shot e few-shot via DeepSeek (`R/llm.R`), mas a UI v0.2 não expõe. Plano em v0.2.1.
- **Sem auditoria LLM no app** (planejado para v0.4).
- **Apenas DeepSeek.** Estrutura permite trocar provedor (`R/llm.R` tem `call_llm()` com provider arg), mas só DeepSeek implementado.
- **Apenas Folha.** Outras fontes exigiriam novos parsers; arquitetura não generaliza sem refactor.

---

### Ao trabalhar aqui

- Manter as invariantes (seção acima).
- Schema novo? Criar `migrations/000N_descrição.sql`. `db_migrate()` aplica em ordem automaticamente. Nunca editar migrations antigas em produção.
- Antes de mexer em parsers, validar com `inspect_*` em URLs de cada era.
- Testes vão para `tests/testthat/` (placeholder por enquanto; bom alvo: snapshot HTML por era).
- Mexeu na documentação? Rodar `cd website && quarto render` para regenerar `docs/`, commitar `docs/` junto. Não rodamos GH Action ainda — é build local + commit.
- **Não recriar `DESCRIPTION` / `NAMESPACE` / `inst/`** sem discussão explícita com o usuário. A decisão de não ser pacote foi tomada conscientemente (ver `website/sobre.qmd`).
