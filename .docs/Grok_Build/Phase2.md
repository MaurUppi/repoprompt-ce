# Phase 2 — Headless + discovery + deferred product surfaces

**Status:** PARTIAL — implemented C + headless polling + D root-cause; A/B documented non-goal
**Parent:** [Planning.md](./Planning.md)
**Depends on:** [Phase1.md](./Phase1.md) **COMPLETE**

---

## Goal

Close Phase 1 residuals and reach **Cursor-like parity** beyond the Agent Mode MVP path:

1. Headless / discovery / polling lifecycle
2. Product surfaces Phase 1 intentionally skipped (Oracle, Model Presets, reasoning effort UI)
3. Live RepoPromptCE MCP tool exposure inside a Grok ACP sessions

---

## Implementation status (2026-07-20)

| Area | Status |
| --- | --- |
| **C** Reasoning effort UI + ACP apply | **Done** |
| Headless + model polling wiring | **Done** (Agent Mode + Context Builder subscribe; headless provider applies effort) |
| **D** Live RepoPromptCE MCP | **Root-caused**; inject shape OK; socket connection is the live gate |
| **A/B** Oracle + Model Presets | **Documented non-goal** for this phase (see below) |
| **E** Non-ad-hoc UI smoke | Optional; no Apple Development identity on this machine |

---

## C — Reasoning effort (done)

**Grok protocol facts:**

- Base model: `grok-4.5` via legacy `models` / `session/set_model`
- Effort: `high` / `medium` / `low` via `session/set_mode` (not `session/set_config_option`)
- Grok does **not** advertise modern ACP `configOptions`

**CE changes:**

- `GrokBuildModelSpecifier` + `GrokBuildReasoningEffort`
- Catalog expands to `grok-4.5:high|medium|low` (display **Grok 4.5 High/Medium/Low**)
- Bare `grok-4.5` remains valid (default effort **high**)
- `ACPAgentSessionController`: Grok paths for `session/set_model` + `session/set_mode`; parse legacy models + `_meta.reasoningEfforts`
- `ACPIntegratedAgentModeRunner` + headless provider apply base model + effort
- Launch `-m` strips effort suffix

**Tests:** `GrokBuildModelSpecifierTests`, launch-resolver strip-effort case

---

## Headless + polling (done)

- `AgentModeViewModel` / `ContextBuilderAgentViewModel`: Grok Build model polling subscribe/stop (Cursor parity)
- Existing `GrokBuildACPHeadlessAgentProvider` + `GrokBuildACPModelPollingService` (Connect path) retained
- Window shutdown already stops `GrokBuildACPModelPollingService.shared`

---

## D — Live RepoPromptCE MCP (root cause)

**Inject shape:** OK (session `mcpServers` CE `acpJSONObject`; Grok accepts it).

**Live failure:** when Grok spawns RepoPromptCE, CLI logs:

```text
Bootstrap connection lost (... SocketProxyError.connectionRefused)
```

RepoPromptCE MCP is a **socket client** into the running CE app. If the app MCP bootstrap socket is not accepting (app not running, wrong identity path, ad-hoc timing), tools never register. Grok’s user-local MCPs (`tasks`, `context-mode`, …) still appear.

**Not a blocker for missing Apple Developer Program** — ad-hoc is fine; the gate is **live app MCP socket readiness**, not signing.

**Phase 2 residual (follow-up):** when CE app is running with MCP listening, prove one tool call from a Grok Agent Mode turn; optionally improve spawn diagnostics / wait-for-socket.

---

## A/B — Oracle Model + Model Presets (non-goal for Phase 2)

**Product decision:** keep Oracle / Model Presets on the **chat `AIModel` / `AIProviderType`** path (Claude Code, Codex CLI, Cursor CLI, OpenCode, HTTP providers).

Grok Build remains:

- Agent Mode CLI agent
- Context Builder **Agent** (discovery)
- **Not** Oracle analysis / Model Preset backend

Rationale: Oracle needs a full `AIProviderType` + `*CLIProvider` (see Cursor/OpenCode), ~many exhaustive switches, separate from ACP Agent Mode. Phase 3 may revisit if product wants Grok as Oracle.

---

## Non-goals (unchanged)

- Recommendation ranking / onboarding polish (→ Phase 3)
- SwiftPM provider package extract
- Changing HTTP `GrokProvider`
- Full `x.ai/*` extension surface beyond effort/mode/model needed for catalog

---

## Exit criteria

- [x] Headless path present (`GrokBuildACPHeadlessAgentProvider`); polling wired in Agent Mode + Context Builder
- [x] Model polling lifecycle start/stop with selection + window close
- [x] Reasoning effort options in catalog (High/Medium/Low) when Grok Build available
- [x] Oracle + Model Presets: **documented permanent Phase 2 non-goal** (Agent Mode / CB agent only)
- [~] Live RepoPromptCE MCP: inject OK; socket connection residual
- [x] Context Builder can select Grok + effort options via same catalog
- [x] Focused tests + commits

---

## Key files

- `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/GrokBuildModelSpecifier.swift`
- `Sources/RepoPrompt/Infrastructure/AI/ACP/ACPAgentSessionController.swift`
- `Sources/RepoPrompt/Features/AgentMode/Models/ModelSelection/AgentModelCatalog.swift`
- `Sources/RepoPrompt/Features/AgentMode/ViewModels/AgentModeViewModel.swift`
- `Sources/RepoPrompt/Features/ContextBuilder/ViewModels/ContextBuilderAgentViewModel.swift`
- `Tests/RepoPromptTests/AgentMode/GrokBuildModelSpecifierTests.swift`
