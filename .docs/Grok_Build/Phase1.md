# Phase 1 — MVP (Cursor-parity core path)

**Status:** Nearly complete — Connect live OK; Agent Models picker gap fixed (rebuild needed)
**Parent:** [Planning.md](./Planning.md)
**Depends on:** [Phase0.md](./Phase0.md) frozen decisions + [Phase0-evidence.md](./Phase0-evidence.md)

---

## Goal

Ship the smallest complete user path:

**CLI Providers → Connect Grok Build → Agent Mode multi-turn ACP → RepoPrompt MCP tools → model pick.**

---

## Scope checklist

| # | Item | Status |
| --- | --- | --- |
| 1 | Launch + Connect (PATH, auth, CLI card) | **Done** — live: Connected, 1 model available, permissions UI |
| 2 | ACP interactive Agent Mode wiring | **Done** (code) — live turn still to confirm |
| 3 | RepoPrompt MCP session inject | **Done** (code) — live MCP tool call still to confirm |
| 4 | Model catalog minimum (`grok-4.5` + discovery) | **Partial → fixed** — see note below |
| 5 | Permissions binding | **Done** — Default / Full Access visible when connected |
| 6 | Focused tests + product build | **Done** |
| 7 | Commits + preflight | **Done** (including stdio preflight fix) |

### Model pick note (2026-07-20)

**CLI Providers “1 model available”** is expected after Connect (catalog/discovery for the Grok Build card).

**Agent Models** picker previously **could not** list Grok Build because `AgentModelCatalog.selectableAgents` omitted `.grokBuild` (bug/gap, not intentional product design). Fixed by adding `.grokBuild` to `selectableAgents` and `supportedCLIProviderAgents`. Rebuild/relaunch required to pick **Grok Build** + **grok-4.5** in Agent Mode.

**Oracle Model** (ask_oracle / plan-review / Context Builder analysis) is a **different** surface from Agent Models. It uses chat/CLI oracle backends (e.g. Codex GPT-5.6 Sol High). **Not** selecting Grok Build there is **expected** for Phase 1 (not in scope to replace Oracle with Grok Build).

---

## Non-goals (unchanged)

- Recommendations wizard polish
- Full headless parity (→ Phase 2)
- `x.ai/*` ACP extensions
- Claude plugin package
- Changing HTTP `GrokProvider`
- Making Oracle Model use Grok Build

---

## Frozen inputs from Phase 0

| Item | Value |
| --- | --- |
| Launch | `grok` + `["agent","stdio"]`; model: `["agent","-m",id,"stdio"]` |
| Auth | `authenticate` / `cached_token`; user `grok login` |
| MCP | Session `mcpServers` CE shape |
| Default model | `grok-4.5` |
| Source dir | `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/` |

---

## Exit criteria

- [x] Connect works from CE app (live: Connected badge)
- [ ] Agent Mode: **select Grok Build + model** (fixed in catalog; needs rebuild)
- [ ] Agent Mode turn streams assistant text
- [ ] RepoPrompt MCP tool callable when MCP server available
- [x] Focused tests + product build green
- [x] Commits with contribution preflight

---

## Live verification remaining

1. Rebuild/relaunch CE with selectableAgents fix.
2. Agent Models → choose **Grok Build** → **grok-4.5**.
3. Send one Agent Mode message; confirm stream.
4. Optional: MCP tool call (e.g. tree/windows) if MCP is up.
