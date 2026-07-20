# Phase 1 — MVP (Cursor-parity core path)

**Status:** COMPLETE (core path live-verified 2026-07-20)
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
| 2 | ACP interactive Agent Mode wiring | **Done** — live agent_run completed with streamed text |
| 3 | RepoPrompt MCP session inject | **Done (code)** — session `mcpServers` CE shape; live tool surface still residual (see note) |
| 4 | Model catalog minimum (`grok-4.5` + discovery) | **Done** — `selectableAgents` includes `.grokBuild`; `list_agents` → `grokBuild:grok-4.5` |
| 5 | Permissions binding | **Done** — Default / Full Access visible when connected |
| 6 | Focused tests + product build | **Done** |
| 7 | Commits + preflight | **Done** |

### Live verification evidence (2026-07-20)

Rebuild with catalog fix (`ALLOW_ADHOC_SIGNING=1 make dev-run`), then CE debug MCP:

1. `agent_manage op=list_agents` lists **Grok Build** with `grokBuild:grok-4.5` (not marked unavailable).
2. `agent_run start` with `model_id=grokBuild:grok-4.5` → session started as Agent **Grok Build** · `grok-4.5`.
3. Wait completed; assistant output: `CE_GROK_BUILD_PHASE1_OK`.
4. Optional MCP tool probe: agent reported only Grok-user MCP (`tasks`); RepoPromptCE tools not surfaced in that turn. Session inject is still wired in `GrokBuildACPAgentProvider` (`includeRepoPromptMCPServer: true`). Residual live MCP handshake/tool exposure → track in Phase 2/polish if needed.

**Oracle Model** remains a separate surface; not selecting Grok Build there is **expected** (Phase 1 non-goal).

### Model pick note

**CLI Providers “1 model available”** is Connect/catalog for the Grok Build card.

**Agent Models** requires `.grokBuild` in `AgentModelCatalog.selectableAgents` (fixed in `b05a95d1`). After rebuild, UI and `list_agents` both expose Grok Build.

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
- [x] Agent Mode: **select Grok Build + model** (`list_agents` + agent_run `grokBuild:grok-4.5`)
- [x] Agent Mode turn streams assistant text (`CE_GROK_BUILD_PHASE1_OK`)
- [x] RepoPrompt MCP inject wired; live tool call residual (not blocking MVP core path)
- [x] Focused tests + product build green
- [x] Commits with contribution preflight

---

## Residual (not Phase 1 blockers) → [Phase2.md](./Phase2.md)

Phase 1 intentionally did **not** ship these; they are scoped in Phase 2:

| Item | Phase 1 stance | Phase 2 section |
| --- | --- | --- |
| Oracle Model cannot select Grok Build | Expected non-goal | **A** |
| Model Presets cannot select Grok | Expected (Oracle `AIModel` path) | **B** |
| No Reasoning Low/Medium/High for `grok-4.5` | Expected min catalog | **C** |
| Live RepoPromptCE MCP tools not listed in Grok session | Inject code done; live residual | **D** |
| Headless / polling / richer discovery | Out of Phase 1 MVP | Headless + discovery |
| UI smoke under non-ad-hoc signing | Optional confidence | **E** |

---

## Key commits

- `6688eb8c` feat: add Grok Build as Cursor-parity ACP CLI provider
- `edb12179` fix: accept Grok stdio help as ACP preflight advertisement
- `b05a95d1` fix: include Grok Build in Agent Models selectable catalog
