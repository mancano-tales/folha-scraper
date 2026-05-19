# Folha Scraper

Coletor sistemático e classificador automático de notícias da Folha de São Paulo para pesquisa acadêmica. Suporta múltiplos projetos de pesquisa lado a lado, compartilhando um banco de artigos coletados.

> **Origem.** Spinoff do pipeline desenvolvido para a dissertação `Mancano2026-MA-Thesis` (subpasta `4-DA-Code/2026-05_Folha_Scraper`). A versão da tese permanece congelada como artefato; este repositório é a versão genérica, multi-projeto, voltada para uso continuado em pesquisa.

---

## Conceito

Cada pesquisa é um **projeto**:

```
Project { nome, descrição, datas, temas[], keywords[], few-shot[] }
                   │
                   ▼
            artigos (URL-keyed, compartilhados entre projetos)
                   │
                   ▼
            classificações (por-projeto, porque relevância é teoria-dependente)
```

**A coleta de fulltext acontece uma vez por URL.** Se o projeto B busca uma keyword que retorna um artigo já coletado pelo projeto A, o texto é reutilizado sem custo. Apenas a classificação LLM é refeita para projeto B (porque os critérios de relevância e a grade temática são específicos).

---

## Estado atual (v0.2)

| Capacidade | Status |
|---|---|
| Banco SQLite com schema multi-projeto | ✅ |
| Coleta de busca paginada | ✅ |
| Coleta de fulltext (3 eras de layout da Folha) | ✅ |
| Dedup por URL + fuzzy por título | ✅ |
| Classificação LLM via DeepSeek (zero-shot e few-shot) — biblioteca | ✅ |
| Datas opcionais por keyword (sobrescrevem datas do projeto) | ✅ |
| Importação do corpus da tese (legacy CSV → SQLite) | ✅ |
| CLI (create-project, add-keyword, run, refresh-fulltext) | ✅ |
| **App Shiny (v0.2)** — projetos, keywords, coleta com log live, corpus browser | ✅ |
| App Shiny — features LLM (anotação few-shot, classificar) | ⏳ v0.2.x |
| Exportação Excel multi-aba | ⏳ v0.3 |

---

## Pré-requisitos

R 4.2+ com os pacotes da biblioteca:

```r
install.packages(c(
  "DBI", "RSQLite", "httr2", "rvest", "dplyr", "purrr", "tidyr",
  "stringr", "stringdist", "stringi", "glue", "lubridate",
  "jsonlite", "readr", "tibble"
))
```

Para o Shiny app (adicional):

```r
install.packages(c("shiny", "bslib", "DT", "callr", "htmltools"))
```

Chave da API DeepSeek em `~/.Renviron`:

```
DEEPSEEK_API_KEY=sk-...
```

Veja [`.Renviron.example`](.Renviron.example).

---

## Uso (CLI)

A partir da raiz do repositório:

```r
# Criar um projeto
Rscript scripts/cli.R new-project \
  --name "Reforma do ProUni" \
  --start 2003-01-01 --end 2016-12-31 \
  --themes "ProUni; FIES; Cotas"

# Adicionar keywords
Rscript scripts/cli.R add-keyword --project "Reforma do ProUni" --keyword "ProUni"
Rscript scripts/cli.R add-keyword --project "Reforma do ProUni" \
  --keyword "Lei de Cotas" --start 2010-01-01

# Listar projetos
Rscript scripts/cli.R list-projects

# Rodar coleta (busca + fulltext + dedup)
Rscript scripts/cli.R run --project "Reforma do ProUni" --skip-llm

# Coleta + classificação LLM
Rscript scripts/cli.R run --project "Reforma do ProUni"
```

Ou interativamente no R:

```r
source("R/db.R"); source("R/utils.R"); source("R/scrape.R")
source("R/dedup.R"); source("R/projects.R"); source("R/llm.R")
source("R/pipeline.R")

db <- db_connect()
project_id <- project_create(db, name = "Teste",
                              date_start = "01/01/2010", date_end = "31/12/2015",
                              themes = c("ProUni", "FIES"))
project_add_keyword(db, project_id, "ProUni")
run_collection(db, project_id, skip_llm = TRUE)
db_close(db)
```

---

## Uso (Shiny app)

A partir da raiz do repositório:

```r
source("R/run_app.R")
run_app()
```

ou via Rscript:

```bash
Rscript scripts/run_app.R              # abre no navegador padrão
Rscript scripts/run_app.R --port 4321  # porta fixa
Rscript scripts/run_app.R --no-browser # roda sem abrir
```

O app tem três abas:

1. **Projetos** — DT com todos os projetos, botão *+ Novo projeto* abre modal com formulário (nome, datas, temas, descrição). Clique numa linha para abrir o projeto.

2. **Projeto atual** — dividido em 4 sub-abas:
   - *Visão geral*: cards de stats (keywords, artigos, % com fulltext) + histórico de rodadas
   - *Keywords*: tabela editável; adicionar/remover keyword; datas opcionais sobrescrevem as do projeto
   - *Coleta*: botão **▶ Rodar coleta** que dispara processo em background (via `callr`); log em tempo real, atualizado a cada segundo. A coleta inclui busca + dedup + fulltext (sem LLM nesta versão)
   - *Corpus*: DT do corpus do projeto com filtros (era, status fulltext, período, busca textual); clique numa linha abre modal com fulltext

3. **Sobre** — descrição, versão, link pro repositório

> A coleta roda em processo separado. Você pode navegar para outras abas durante uma rodada — o log continua atualizando quando você volta.

---

## Importando o corpus da dissertação

Se você tem o `corpus_master.csv` da pasta da tese:

```r
Rscript scripts/import_thesis_corpus.R \
  --csv "C:/Users/Mancano/Documents/MancanoSync/Mancano2026-MA-Thesis/4-DA-Code/2026-05_Folha_Scraper/data/master/corpus_master.csv" \
  --project-name "Mancano2026-MA-Thesis"
```

O script popula a tabela `articles` (todos os artigos viram parte do banco compartilhado) e cria um projeto com as keywords e classificações já existentes.

---

## Localização dos dados

```
folha-scraper/
├── R/                          ← lógica (biblioteca)
├── app/                        ← Shiny app (global.R + app.R)
├── inst/migrations/            ← SQL versionado
├── scripts/                    ← entrypoints (CLI, importação, run_app)
├── tests/                      ← testthat (placeholder)
└── data/
    └── folha.sqlite            ← banco local (gitignored)
```

O banco é local. Backup é cópia do arquivo `data/folha.sqlite`.

---

## Roadmap

- ~~**v0.2** — Shiny app: lista de projetos, formulário de criação, monitor de rodada, browser de corpus~~ ✅
- **v0.2.1** — Anotação few-shot no app, exposição das features LLM, botão "classificar" por projeto
- **v0.3** — Exportação Excel multi-aba por projeto
- **v0.4** — Auditoria de classificação LLM no app
- **futuro** — Múltiplas fontes (Estadão, Globo), provedores LLM alternativos (Claude, GPT), agendamento de coletas periódicas

---

## Licença

MIT.
