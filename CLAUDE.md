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

- `cli.R` — dispatcher para uso via `Rscript`
- `import_thesis_corpus.R` — migra CSV da tese → SQLite

**Schema** em `inst/migrations/0001_init.sql`. Versões futuras: `0002_*.sql`, etc.

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

## O que NÃO está implementado

- **Sem Shiny.** Tudo via R console ou `Rscript scripts/cli.R`.
- **Sem exportação Excel ainda.** Função `export_excel(db, project_id)` existe como TODO em `R/export.R` (placeholder).
- **Sem auditoria LLM no app** (planejado para v0.4).
- **Apenas DeepSeek.** Estrutura permite trocar provedor (`R/llm.R` tem `call_llm()` com provider arg), mas só DeepSeek implementado.
- **Apenas Folha.** Outras fontes exigiriam novos parsers; arquitetura não generaliza sem refactor.

---

## Ao trabalhar aqui

- Manter as invariantes (seção acima).
- Schema novo? Criar `inst/migrations/000N_descrição.sql` e atualizar `db_migrate()`. Nunca editar migrations antigas em produção.
- Antes de mexer em parsers, validar com `inspect_*` em URLs de cada era.
- Testes vão para `tests/testthat/` (placeholder por enquanto; bom alvo: snapshot HTML por era).
