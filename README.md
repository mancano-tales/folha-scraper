# folha-scraper

Coletor multi-projeto de notícias da Folha de São Paulo para pesquisa acadêmica. Pipeline R + SQLite + Shiny: você clona, abre, e roda.

📖 **Documentação completa: <https://mancano-tales.github.io/folha-scraper/>**

> **Origem.** Spinoff do pipeline desenvolvido para a dissertação `Mancano2026-MA-Thesis`. A versão da tese permanece congelada como artefato; este repositório é a versão genérica, multi-projeto, voltada para uso continuado em pesquisa.

---

## Modelo de uso: clone-and-run

Este repositório **não é um pacote R instalável**. É um aplicativo: você clona o repo, instala dependências R uma vez, e roda. Cada clone tem seu próprio banco SQLite local em `data/folha.sqlite`. Esse modelo facilita iteração rápida e deixa óbvio onde os dados vivem.

> Justificativa completa dessa escolha está em [Sobre → Por que clone-and-run](https://mancano-tales.github.io/folha-scraper/sobre.html#por-que-clone-and-run-e-não-um-pacote-r).

---

## Quick start

```bash
git clone https://github.com/mancano-tales/folha-scraper.git
cd folha-scraper
```

Em R (na raiz do repo):

```r
# Dependências da biblioteca (instalar uma vez)
install.packages(c(
  "DBI", "RSQLite", "httr2", "rvest", "dplyr", "purrr", "tidyr",
  "stringr", "stringdist", "stringi", "glue", "lubridate",
  "jsonlite", "readr", "tibble"
))

# Dependências do Shiny app (instalar uma vez)
install.packages(c("shiny", "bslib", "DT", "callr", "htmltools"))

# Lança o app
source("R/run_app.R")
run_app()
```

Para um passo-a-passo guiado do clone à primeira coleta, ver [Começar](https://mancano-tales.github.io/folha-scraper/comecar.html).

---

## Capacidades (v0.2)

| | |
|---|---|
| Banco SQLite com schema multi-projeto | ✅ |
| Busca paginada na Folha (com delays de respeito ao servidor) | ✅ |
| Coleta de fulltext cobrindo 3 eras de layout (1994–2003, 2003–2015, 2015+) | ✅ |
| Deduplicação por URL + fuzzy por título | ✅ |
| Datas opcionais por keyword | ✅ |
| Importação de corpus CSV pré-existente | ✅ |
| CLI (criar projeto, adicionar keyword, rodar, refresh-fulltext) | ✅ |
| **App Shiny** com Projetos, Coleta com log live, Corpus browser | ✅ |
| Classificação LLM via DeepSeek — biblioteca | ✅ |
| Classificação LLM exposta no app | ⏳ v0.2.x |
| Exportação Excel multi-aba | ⏳ v0.3 |

---

## Estrutura do repositório

```
folha-scraper/
├── R/                    ← módulos R (biblioteca)
│   ├── db.R              ← conexão SQLite + migrations
│   ├── utils.R           ← logging, HTTP, parsing de datas
│   ├── scrape.R          ← busca + fulltext (3 eras)
│   ├── dedup.R           ← fuzzy dedup
│   ├── projects.R        ← CRUD de projetos/keywords
│   ├── llm.R             ← classificação DeepSeek (não exposta no app v0.2)
│   ├── pipeline.R        ← orquestrador (run_collection)
│   ├── export.R          ← project_corpus + stub p/ Excel
│   └── run_app.R         ← lança o Shiny
├── app/
│   ├── global.R          ← bootstrap do Shiny
│   └── app.R             ← UI + server (~700 linhas)
├── scripts/
│   ├── cli.R             ← CLI via Rscript
│   ├── run_app.R         ← launcher do app
│   └── import_thesis_corpus.R
├── migrations/           ← SQL versionado
│   └── 0001_init.sql
├── website/              ← fonte do site Quarto
│   ├── _quarto.yml
│   ├── index.qmd
│   ├── comecar.qmd
│   ├── referencia.qmd
│   └── sobre.qmd
├── docs/                 ← site Quarto renderizado (servido via GH Pages)
└── data/folha.sqlite     ← banco local (gitignored)
```

---

## Uso via CLI

Alternativa sem o app, para automação ou pipelines:

```bash
# Criar projeto
Rscript scripts/cli.R new-project \
  --name "Reforma do ProUni" \
  --start 2003-01-01 --end 2016-12-31 \
  --themes "ProUni; FIES; Cotas"

# Adicionar keywords
Rscript scripts/cli.R add-keyword --project "Reforma do ProUni" --keyword "ProUni"
Rscript scripts/cli.R add-keyword --project "Reforma do ProUni" \
  --keyword "Lei de Cotas" --start 2012-08-29

# Listar / inspecionar
Rscript scripts/cli.R list-projects
Rscript scripts/cli.R show-project --project "Reforma do ProUni"

# Rodar coleta
Rscript scripts/cli.R run --project "Reforma do ProUni" --skip-llm

# Reaproveitar fulltext caso o parser melhore depois
Rscript scripts/cli.R refresh-fulltext --project "Reforma do ProUni" --status "paywall"
```

---

## Importando um corpus pré-existente

Se você tem um `corpus_master.csv` (ex.: da pasta da tese):

```bash
Rscript scripts/import_thesis_corpus.R \
  --csv "/caminho/para/corpus_master.csv" \
  --project-name "Mancano2026-MA-Thesis"
```

O script popula a tabela `articles` e cria um projeto com as keywords e classificações já existentes.

---

## Roadmap

- **v0.2** ✅ — Shiny app, projetos, coleta, corpus browser
- **v0.2.x** — LLM exposto no app, anotação few-shot interativa
- **v0.3** — Exportação Excel multi-aba
- **v0.4** — Auditoria de classificações LLM
- **Futuro** — Múltiplas fontes (Estadão, Globo), provedores LLM alternativos, agendamento

---

## Licença

MIT.
