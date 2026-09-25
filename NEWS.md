# NEWS — folha-scraper

Log de decisões deste repositório. Entrada mais recente no topo; nunca reescrito.

## 2026-09-25 09:31 — Backup do banco no Drive e no SSD

O banco `data/folha.sqlite` só existia no disco local. Uma cópia consistente (API de backup do SQLite;
`integrity_check = ok`; 43 artigos) foi para o Google Drive do autor e para o SSD, conferida por md5.
Entraram o `.data-source` (`folha_db_snapshot`), a cópia do resolvedor `R/data_source.R` (v1.2.0),
que nenhum script do app carrega (os módulos são carregados por lista explícita), e uma seção no
`README.md`. O app continua lendo e escrevendo o banco local, e cada clone começa com o seu próprio.

**Metadados de Execução**:
- **Data/Hora**: 2026-09-25 09:31 (Horário Local)
- **Agente**: Claude Code / Claude Opus 5.5 / desktop (sessão "Hub e Drive pendências")
- **Mensagem do Commit**: "chore(data): backup do banco no Drive e no SSD"
- **Arquivos afetados**: `.data-source`, `R/data_source.R`, `README.md`, `NEWS.md`
