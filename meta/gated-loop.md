---
title: Gated loop — unattended task-convergence pattern
type: meta
subtype: runbook
status: active
updated: 2026-07-31
---

The pattern for grinding one build/fix task to green unattended, safely. It is plan → build → verify applied in a loop, with a gate the agent cannot talk its way past.

Requires the `agents/` personas (bootstrap `--with-agents`). Costs more tokens (dispatched subagents + a fresh reviewer per pass), so it's opt-in.

## When to use it

A task where "done" is a **green command** (a failing test to fix, an IaC plan to make clean, a lint/type sweep, a migration that must converge), not a vibe. **Not** for a prod-mutating change without a machine-verifiable safe gate AND a prepared rollback (see `feedback/safety.md` — never mutate prod blind).

## The rules

- **Exit conditions written FIRST**, before starting: the success criteria (concrete), the command that proves it, the max iterations, and the escalation condition (when to stop and ping instead of looping).
- **One item per pass, fresh context.** The only memory between passes = the filesystem + a running task file.
- **Producer ≠ approver.** The `builder` persona implements; a **hard gate** (a test / compiler / plan exit code, no opinion) plus a **soft gate** (a fresh `code-reviewer` or `infra-reviewer`) decide. The builder never signs off its own work.
- **Signposts on failure.** On a failed gate, write the lesson into the task file before the next pass, so the loop learns instead of repeating.
- **Hard caps.** Max iterations + a token budget. Exit on green, on cap, or after K passes with no progress. No infinite grind.

## Wiring

If your agent runtime has a workflow/orchestration primitive, model it as a pipeline `builder stage → verify stage` with hard caps. Otherwise a plain loop ("keep fixing and re-running until this command exits zero, then stop") plus dispatching the `builder` and a `*-reviewer` persona per pass gets you the same producer ≠ approver structure.

Related: `feedback/safety.md`, the reviewer + builder personas in `harness/agents/`.
