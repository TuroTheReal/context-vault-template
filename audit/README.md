# Audit reports

`/audit-vault --output markdown` writes detailed reports here as `audit-YYYY-MM-DD.md`.

Reports are **gitignored** (artefacts, not vault content). The compact summary of each run is appended to `log.md` for git-tracked history.

To regenerate a report on demand: `/audit-vault --output markdown`.
