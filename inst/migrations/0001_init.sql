-- ============================================================================
-- folha-scraper — Schema inicial (v1)
-- ============================================================================
-- Modelo:
--   articles          : store URL-keyed, COMPARTILHADO entre projetos
--   projects          : cada pesquisa é um projeto isolado
--   project_keywords  : keywords de um projeto (com datas opcionais por keyword)
--   project_articles  : N:N (qual artigo pertence a qual projeto)
--   classifications   : LLM por (projeto × artigo) — relevância é teoria-dependente
--   few_shot_examples : exemplos rotulados por projeto
--   runs              : log de execuções
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- ARTICLES (store compartilhado)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS articles (
  url_clean       TEXT PRIMARY KEY,
  url             TEXT NOT NULL,
  title           TEXT,
  title_norm      TEXT,
  date            TEXT,
  date_raw        TEXT,
  section         TEXT,
  excerpt         TEXT,
  full_text       TEXT,
  era             INTEGER,
  fulltext_status TEXT DEFAULT 'pending',
  collected_at    TEXT NOT NULL,
  fulltext_at     TEXT
);

CREATE INDEX IF NOT EXISTS idx_articles_title_norm ON articles(title_norm);
CREATE INDEX IF NOT EXISTS idx_articles_date       ON articles(date);
CREATE INDEX IF NOT EXISTS idx_articles_status     ON articles(fulltext_status);

-- ----------------------------------------------------------------------------
-- PROJECTS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS projects (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  name            TEXT NOT NULL UNIQUE,
  slug            TEXT NOT NULL UNIQUE,
  description     TEXT,
  date_start      TEXT NOT NULL,
  date_end        TEXT NOT NULL,
  themes_json     TEXT,
  status          TEXT NOT NULL DEFAULT 'active',
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);

-- ----------------------------------------------------------------------------
-- PROJECT_KEYWORDS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_keywords (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id          INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  keyword             TEXT NOT NULL,
  date_start_override TEXT,
  date_end_override   TEXT,
  status              TEXT NOT NULL DEFAULT 'pending',
  n_search_raw        INTEGER NOT NULL DEFAULT 0,
  n_new_added         INTEGER NOT NULL DEFAULT 0,
  n_existing_matched  INTEGER NOT NULL DEFAULT 0,
  added_at            TEXT NOT NULL,
  processed_at        TEXT,
  error_msg           TEXT,
  UNIQUE(project_id, keyword)
);

CREATE INDEX IF NOT EXISTS idx_pkw_project ON project_keywords(project_id);
CREATE INDEX IF NOT EXISTS idx_pkw_status  ON project_keywords(status);

-- ----------------------------------------------------------------------------
-- PROJECT_ARTICLES (N:N entre projetos e artigos)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_articles (
  project_id        INTEGER NOT NULL REFERENCES projects(id)  ON DELETE CASCADE,
  url_clean         TEXT    NOT NULL REFERENCES articles(url_clean) ON DELETE CASCADE,
  matched_keywords  TEXT NOT NULL,
  first_matched_at  TEXT NOT NULL,
  PRIMARY KEY (project_id, url_clean)
);

CREATE INDEX IF NOT EXISTS idx_pa_project ON project_articles(project_id);
CREATE INDEX IF NOT EXISTS idx_pa_url     ON project_articles(url_clean);

-- ----------------------------------------------------------------------------
-- CLASSIFICATIONS (LLM por projeto × artigo)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS classifications (
  project_id      INTEGER NOT NULL REFERENCES projects(id)  ON DELETE CASCADE,
  url_clean       TEXT    NOT NULL REFERENCES articles(url_clean) ON DELETE CASCADE,
  relevant        TEXT,
  justification   TEXT,
  themes          TEXT,
  summary         TEXT,
  model           TEXT,
  n_few_shot      INTEGER,
  error_msg       TEXT,
  classified_at   TEXT NOT NULL,
  PRIMARY KEY (project_id, url_clean)
);

CREATE INDEX IF NOT EXISTS idx_cls_project    ON classifications(project_id);
CREATE INDEX IF NOT EXISTS idx_cls_relevance  ON classifications(project_id, relevant);

-- ----------------------------------------------------------------------------
-- FEW_SHOT_EXAMPLES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS few_shot_examples (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id      INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  url_clean       TEXT REFERENCES articles(url_clean),
  title           TEXT NOT NULL,
  content_excerpt TEXT,
  keywords_matched TEXT,
  relevante       TEXT NOT NULL,
  justificativa   TEXT,
  temas           TEXT,
  resumo          TEXT,
  notes           TEXT,
  added_at        TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_fs_project ON few_shot_examples(project_id);

-- ----------------------------------------------------------------------------
-- RUNS (log de execuções)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS runs (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id       INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  started_at       TEXT NOT NULL,
  finished_at      TEXT,
  status           TEXT NOT NULL DEFAULT 'running',
  phase            TEXT,
  keywords_run     TEXT,
  articles_new     INTEGER NOT NULL DEFAULT 0,
  articles_matched INTEGER NOT NULL DEFAULT 0,
  skip_llm         INTEGER NOT NULL DEFAULT 0,
  error_msg        TEXT
);

CREATE INDEX IF NOT EXISTS idx_runs_project ON runs(project_id);

-- ----------------------------------------------------------------------------
-- SCHEMA VERSIONING
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_version (
  version    INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);
