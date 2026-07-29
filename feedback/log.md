# Feedback trace ledger

Provenance for the rules in `feedback/*.md`. The rule BODIES stay behavioral (what to do); the TRACE lives here (why + episode). Write-time fidelity guard: every rule traces to at least one line below (date · session id · what you said/did on what the AI proposed). Not loaded at read-time, so the loaded context stays lean.

Format: one `## <pillar>` section, each rule a bullet:
`- **<rule>** — <date> · session <id> · what you said/did on what the AI proposed` (a key quote may be kept).

<!-- /learn-feedback adds a `## <pillar>` section the first time that pillar gets a rule. Empty until the first run. -->
