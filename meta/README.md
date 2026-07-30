# Meta layer

Documentation of your **harness / setup itself**, not domain knowledge: how the vault ecosystem is wired, how your skills and scheduled agents work, runbooks for your automation.

On-demand DETAIL docs (read when working ON the setup); a short pointer-summary lives in `memory/`, so the agent knows the doc exists and reads it when relevant.

Distinct from `notes/`: `meta/` is about the **machinery**, `notes/` is about the **work**.

## File format

```yaml
title: <human-readable>
type: meta
subtype: reference | runbook | backlog   # optional
status: active
updated: YYYY-MM-DD
```

Free-form body. Link related meta docs with `[[name]]`.
