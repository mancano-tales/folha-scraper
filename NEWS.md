# NEWS — folha-scraper

## 2026-09-26 — Governança comum do ecossistema (v2026-09-26c)

Aplicado o bloco de governança comum mantido no hub (`mancano-tales/mancano-repo-hub`, `tools/governanca-comum/`): planos com issue (`tools/plano_issue.py`), aprovação só no chat e no plano, mensagens de agentes como pedido, cabeçalho de agente, branch/PR opcionais, `NEWS.md` junto com a mudança, **datas sem hora** e **exportar conversa só quando o autor pedir**. O bloco fica entre marcadores no `AGENTS.md`; o que é específico deste repositório foi preservado.

**Metadados de Execução**:
- **Data**: 2026-09-26
- **Agente**: Claude Code / Claude Opus 5.5 / Claude Code on the web, via `tools/sync_governanca.py` do hub
- **Mensagem do Commit**: "docs(governance): governanca comum v2026-09-26c"
- **Arquivos afetados**: AGENTS.md, CLAUDE.md, NEWS.md, tools/plano_issue.py, .claude/settings.json

## 2026-09-26 — Governança comum do ecossistema (v2026-09-26)

Aplicado o bloco de governança comum mantido no hub (`mancano-tales/mancano-repo-hub`, `tools/governanca-comum/`): planos com issue (`tools/plano_issue.py`), aprovação só no chat e no plano, mensagens de agentes como pedido, cabeçalho de agente, branch/PR opcionais, `NEWS.md` junto com a mudança e **datas sem hora**. O bloco fica entre marcadores no `AGENTS.md`; o que é específico deste repositório foi preservado.

**Metadados de Execução**:
- **Data**: 2026-09-26
- **Agente**: Claude Code / Claude Opus 5.5 / desktop, via `tools/sync_governanca.py` do hub
- **Mensagem do Commit**: "docs(governance): governanca comum v2026-09-26"
- **Arquivos afetados**: AGENTS.md, CLAUDE.md, NEWS.md, tools/plano_issue.py, .claude/settings.json

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
