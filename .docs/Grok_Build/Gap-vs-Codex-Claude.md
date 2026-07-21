# Grok Build — Gap analysis vs Codex / Claude

**Date:** 2026-07-21
**Status:** Analysis (no implementation commitment)
**Audience:** maintainers sequencing product polish after Phase 0–3 core wiring
**Related:** [Planning.md](./Planning.md), [Usage.md](./Usage.md), [Phase3.md](./Phase3.md)
**Architecture authority:** `docs/architecture/provider-plugins.md`

---

## 1. Purpose and comparison frames

This document uses **Codex** and **Claude Code** (plus the Claude-compatible family where it shares the same runtime) as the **product maturity baseline**: the two deepest Agent Mode integrations in RepoPrompt CE.

Grok Build was **not** built on those protocols. Product plan ([Planning.md](./Planning.md)) targets **Cursor CLI–style ACP parity**, not Codex app-server or Claude native SDK. Gaps therefore fall into three classes:

| Class | Meaning | Default action |
| --- | --- | --- |
| **A — Protocol non-goal** | Capability exists only because Codex/Claude use a different runtime | Do not port; document as intentional |
| **B — Product surface gap** | Same *user-facing* unit exists for Codex/Claude (or Cursor), Grok is missing or stubbed | Prioritize by UX / discoverability |
| **C — ACP peer gap** | Cursor/OpenCode have it; Grok’s ACP clone does not (or only partially) | Fair apples-to-apples backlog |

**Severity** (for backlog rows):

| Level | Definition |
| --- | --- |
| **P0** | Broken or misleading for a shipped surface users already see |
| **P1** | First-class product polish (recommendations, onboarding, persistence UX) |
| **P2** | Nice-to-have parity, diagnostics, stress, changelog |
| **P3** | Deep runtime features that only make sense on Codex/Claude protocols |

---

## 2. Runtime architecture (baseline)

Three control planes ship today:

```text
┌─────────────────────────────────────────────────────────────────┐
│ Agent Mode UI / catalog / MCP policy / permissions               │
└───────────────┬─────────────────────┬───────────────────────────┘
                │                     │
    ┌───────────▼──────────┐  ┌───────▼──────────┐  ┌─────────────▼─────────────┐
    │ Codex native         │  │ Claude native    │  │ ACP shared plane            │
    │ app-server           │  │ process + SDK    │  │ OpenCode / Cursor / Grok    │
    │ CodexNativeSession…  │  │ ClaudeNative…    │  │ ACPAgentSessionController   │
    │ CodexCLIProvider     │  │ ClaudeCodeProv…  │  │ *ACPAgentProvider           │
    └──────────────────────┘  └──────────────────┘  │ *CLIProvider (Oracle)       │
                                                    └─────────────────────────────┘
```

| Dimension | Codex | Claude Code (+ compatible) | Grok Build |
| --- | --- | --- | --- |
| Protocol | App-server JSON-RPC (`thread/*`) | Native process / NDJSON SDK | **ACP** `grok agent stdio` |
| Agent kind | `.codexExec` | `.claudeCode` (+ GLM/Kimi/custom) | `.grokBuild` |
| Chat / Oracle type | `AIProviderType.codex` | `.claudeCode` | `.grokBuild` (**≠** HTTP `.grok`) |
| MCP client family | `codex-mcp-client` | `claude-code` | `grok` (+ `grok-*`, `grok-shell-*`) |
| Auth model | ChatGPT / CLI + **managed recovery** | CLI / account + compatible API keys | `grok login` / ACP `cached_token` |
| Approx. provider LOC | Very large (app-server + prefs + integration) | Large (SDK + plugin package + prefs) | Thin ACP clone (~1.2k lines under `GrokBuild/`) |
| Plugin package | No | **Yes** — `RepoPromptClaudeCompatibleProvider` | No (in-app like Cursor) |

**Key paths**

| Area | Codex | Claude | Grok Build |
| --- | --- | --- | --- |
| Provider root | `Infrastructure/AI/Providers/Codex/` | `…/ClaudeCode/` + `ClaudeCodeProvider.swift` | `…/GrokBuild/` |
| Agent Mode coordinator | `Features/AgentMode/Runtime/Codex/…` | `…/Claude/` + ClaudeCompatible adapters | Shared ACP runner (`ACPIntegratedAgentModeRunner`) |
| Oracle / chat | `CodexCLIProvider` | `ClaudeCodeProvider` | `GrokBuildCLIProvider` |
| Identity / factory | `AgentRuntimeProviderService` | same | same |

---

## 3. Functional unit matrix

Legend: **Y** = supported · **P** = partial · **N** = no · **—** = N/A by design

### 3.1 Connect / CLI Providers

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| Settings card (Connect / Test / Sign out) | Y | Y | Y | — | `CLIProvidersSettingsView` |
| Connection flag (`*CLIConnected`) | Y | Y | Y | — | `GrokBuildCLIConnected` |
| Connection notification | Y | Y | Y | — | `.grokBuildConnectionChanged` |
| Connection phase enum / binary probe UX | Y (rich) | Y (binary status) | P | B/C | Grok: bool + error string; no Codex-style phase machine |
| PATH + login-shell hints | Y | Y | Y | — | `CLILaunchProfiles.grokBuild`, `CLIPathHints` |
| Managed auth recovery service | Y | P | N | A/B | Codex `CodexManagedAuthRecoveryService`; Grok only classifies errors → “run grok login” |
| `*IntegrationConfiguration` (persist MCP into CLI config) | Y | Y | **N** | B/C | Codex `~/.codex/config.toml`; Claude `mcp add` / Desktop; Cursor project MCP approval; OpenCode ephemeral config; **no `GrokBuildIntegrationConfiguration`** |
| Compatible backends (multi-vendor on one CLI) | N | Y | N | A | Claude-only product family |
| Secure CLI account entry | Y | Y | Y | — | `GrokBuildCLIAPI` placeholder (no key) |
| Permission secure document | Y | Y | Y | — | `AgentPermissions.GrokBuild.v1` |

### 3.2 Permissions / tool preferences

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| Permission levels | Rich (approval policy + sandbox) | Rich (require / auto-edits / auto / full) | **Minimal** (Default / Full Access) | B/C | Mirrors **Cursor** ACP auto-approve, not Codex/Claude |
| Per-tool toggles (bash, search, …) | Y | Y | N | B/C | UI: `AgentProviderPermissionControlsComponents` treats `.openCode/.cursor/.grokBuild` as no tool panel |
| Prompt delivery modes | N | Y (XML / system override) | N | A | Claude SDK–specific |
| Sandbox / danger full access (OS) | Y | N (CLI permission mode) | N | A | Codex app-server |
| Goal / computer-use workflow | Y | N | N | A | Codex-only |
| Permissions UI icon for client family | Y | Y | **N** | P2 | `PermissionsSettingsView.clientIcon` has no `grok` branch → generic icon |

### 3.3 Agent Mode (multi-turn)

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| Multi-turn streamed session | Y | Y | Y | — | Live smoke Phase 1 |
| Session resume / load | Y (`thread/resume`) | Y (`--resume` / session id) | Y (ACP load) | C | Depends on Grok ACP session durability; less product polish than Codex conversation IDs |
| Persisted provider session fields | Rich (`codexConversationID`, rollout, …) | Claude coordinator state | ACP generic | C | No Grok-specific session header fields |
| Model + effort mid-session | Y (rich) | P | Y | — | Grok: `session/set_model` + `session/set_mode` |
| Effort catalog (High/Medium/Low) | Y (many tiers + service tiers) | Y | Y | B | Grok fixed three efforts; Codex service tiers **N/A** |
| Dynamic model polling | Y | N (static/slots) | Y | — | `GrokBuildACPModelPollingService` |
| MCP inject (RepoPrompt tools) | Y | Y | Y | — | ACP session MCP servers; live `CE_GROK_MCP_OK` |
| Pre-prompt MCP routing required | Y | Y | **N** (like Cursor) | C | `requiresPrePromptAgentModeMCPRouting` false for Cursor/Grok |
| MCP tool grant set | Wide native | Wide native | **Cursor grant set** | B/C | `AgentModeMCPToolPolicy`: Grok shares `cursorGrantedTools` (not Codex/Claude native sets) |
| Context usage UI path | Y | P | P | C | Grouped with openCode/cursor/grok in `AgentModeViewModel+ContextUsage` |
| Context Builder agent | Y | Y | Y | B | Wiring exists; **recommendations hardcode Grok off** (below) |
| Agent skill catalog eligibility | Y | Y | Y | — | Included with codex/openCode/cursor |
| DEBUG raw-event logging keys | Y | Y (`claude_raw_event_*`) | **N dedicated** | P2 | Shared ACP/perf diagnostics only |

### 3.4 Oracle / Chat / Model Presets

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| Headless chat provider | Y | Y | Y | — | `GrokBuildCLIProvider` |
| Factory branch | Y | Y | Y | — | `AIProviderFactory` / `AIModel.providerType` |
| Oracle `models.planning_model` | Y | Y | Y | — | Live `CE_GROK_ORACLE_SMOKE_OK` |
| Model Presets list when connected | Y | Y | Y | — | Phase 3 |
| Dedicated picker menu groups | Y (codex groups) | Y (Claude menus) | P | B/C | Grok uses generic / ACP catalog path; no Codex-style menu grouping |
| Oracle **no MCP inject** | Y (tools disabled) | Y (disallow tools) | Y | — | Text-only headless ACP |
| Distinct from HTTP Grok | — | — | Y | — | `AIProviderType.grok` vs `.grokBuild` |

### 3.5 MCP ecosystem (outside Agent inject)

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| Client identity family | Y | Y | Y | — | `MCPClientIdentity` family `grok` |
| Headless agent client recognition | Y | Y | Y | — | `isHeadlessAgentClient` |
| Install RepoPrompt into **CLI’s own** config for external use | Y | Y | **N** | B | No grok-side MCP config helper |
| Wrapper CLI (`claude-rp` analogue) | N | Y | **N** | B | `CLIPathInstaller` Claude RP only |
| Special long MCP server timeout | Y (10000s) | Y (env) | **—** | A | Only if Grok documents a real need |
| MCP Settings prompts/commands docs | Codex prompts path | Claude commands path | **N** | P2 | `MCPSettingsView` |

### 3.6 Recommendations / onboarding / product defaults

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| `RecommendationProviderKind` case | Y | Y | Y | — | Enum includes `.grokBuild` |
| Status snapshot field | Y | Y | **N** | **P1** | `ProviderStatusSnapshot` has **no** `grokBuildCLI`; only claude/codex/cursor/openAI |
| `recommendationProviderStatusSnapshot` | Y | Y | **N** | **P1** | `APISettingsViewModel` never reports Grok readiness |
| Chat backend recommendation | Y | Y | **N** | **P1** | `ChatBackendKind` = claude/codex/openAI only |
| Context Builder recommendation | Y | Y | **N** | **P1** | Prefers codex → claude → cursor; never Grok |
| MCP agent defaults availability | Y | Y | **Forced false** | **P0/P1** | `mcpAgentAvailabilityContext` sets `grokBuildAvailable: false` always |
| Fallback selectableAgents filter | Y | Y | P | P1 | Filter *allows* grok if enabled, but status path never marks ready |
| Onboarding wizard explicit checks | Y | Y | P | P1 | No Grok-specific status in provider grid (status struct lacks field) |
| Best-practice / featured defaults | Heavy Codex bias | Secondary | **None** | P1 | `BestPracticeProfiles` / selection candidates favor Codex/Claude |
| User-facing Changelog entry | Many | Many | **None** | P2 | Not shipped in a named release note yet |

### 3.7 Telemetry / diagnostics / stress / doctor

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| Sentry agent kind enum | Y | Y | Y | — | `grok_build` |
| Recovery / stall telemetry events | Y | P | N | A/P2 | Codex-specific recovery paths |
| Stress harness first-class fixtures | Y | P | **N** | P2 | Defaults to Codex replay |
| Doctor provider install check | N (general) | N | N | — | Doctor is toolchain/debug CLI, not `codex`/`claude`/`grok` install |
| Context Builder launch validation probe | Y | Y | P | C | Startup validation probes claude/codex/openCode/cursor; Grok relies on connect flag + model sub more than full probe set |

### 3.8 Tests

| Unit | Codex | Claude | Grok | Gap class | Notes |
| --- | --- | --- | --- | --- | --- |
| Focused Agent Mode suite | Large `AgentMode/Codex/*` | `AgentMode/ClaudeCompatible/*` | **Minimal** | P1 | Launch resolver + specifier only |
| Oracle / catalog tests | Y | Y | Y | — | `GrokBuildOracleModelCatalogTests` |
| MCP identity tests | Y | Y | Y | — | `MCPClientIdentityGrokFamilyTests` |
| Integration config tests | Y | Y | N | B | No integration module |
| Package plugin tests | N | Y | N | A | Claude package only |

---

## 4. What already matches “good enough” core

These are **not** gaps for MVP correctness (Phases 1–3 closed on smoke):

| Surface | Evidence |
| --- | --- |
| CLI Providers Connect | UI + `testGrokBuildConnection` |
| Agent Models + effort | Catalog High/Medium/Low; live agent_run |
| Agent Mode ACP + MCP inject | Phase 2 `CE_GROK_MCP_OK` |
| Context Builder agent selectability | Availability when connected |
| Oracle + Model Presets | Phase 3 live `CE_GROK_ORACLE_SMOKE_OK` |
| Secure permission doc + Default/Full Access | Cursor-like |
| MCP family identity | Versioned `grok-*` / `grok-shell-*` → family `grok` |
| Telemetry kind | `grok_build` |
| Distinct from xAI HTTP Grok | Separate `AIProviderType` |

---

## 5. Prioritized gap backlog

### P0 — Correctness / misleading product state

| ID | Gap | Why it matters | Suggested direction |
| --- | --- | --- | --- |
| G-01 | Recommendations force `grokBuildAvailable: false` in MCP agent defaults context | User can Connect Grok; wizard / MCP agent defaults still pretend Grok is unavailable | Thread real `isGrokBuildConnected` (+ verified flag) into `mcpAgentAvailabilityContext` |
| G-02 | `ProviderStatusSnapshot` omits Grok entirely | Enabling `.grokBuild` in recommendation filters has no status bit to become “ready” | Add `grokBuildCLI: Availability` (+ `filtered`, grids, `hasAnyCLIAgentReady`) |

### P1 — Product parity users notice

| ID | Gap | Baseline | Suggested direction |
| --- | --- | --- | --- |
| G-10 | Chat / Oracle **not** recommended when only Grok is connected | Codex/Claude drive chat backend recs | Optional `ChatBackendKind.grokBuild` **or** map Oracle planning model to `grokbuild_custom_*` when Grok ready and others not |
| G-11 | Context Builder recommendation never picks Grok | codex → claude → cursor | Add Grok after Cursor (or configurable order) when connected |
| G-12 | No Best Practice / default selection candidates for Grok | Codex/Claude dominate `SelectionCandidate` lists | Add maintainable defaults (e.g. `grok-4.5:medium`) behind product policy |
| G-13 | Onboarding / recommendation UI status grid ignores Grok | Shows Claude/Codex/Cursor | Surface Grok row when `RecommendationProviderKind` includes it |
| G-14 | Thin automated tests vs Codex/Claude suites | Resume, MCP bootstrap, permission profile | Add ACP-focused tests: connect error classification, effort apply, MCP family policy, headless Oracle raw round-trip |
| G-15 | No `GrokBuildIntegrationConfiguration` | Codex/Claude/OpenCode install helpers | Only if Grok documents a user-level MCP config path; otherwise document “inject-only” as intentional |
| G-16 | MCP tool grant set = Cursor subset | Codex/Claude wider native grants | Revisit whether Grok Agent Mode needs broader capability set after real usage |
| G-17 | Cached startup validation does not probe Grok like Cursor/Codex | Stale “connected” after uninstall | Add `probeCachedGrokBuildConnection` into context-builder validation task |

### P2 — Polish / ops

| ID | Gap | Suggested direction |
| --- | --- | --- |
| G-20 | Changelog / release notes | Ship with next CE release that includes Grok Build |
| G-21 | Permissions client icon for `grok` | Add SF Symbol branch next to codex/claude/cursor |
| G-22 | Claude-style raw event DEBUG settings for Grok ACP | Optional shared ACP raw log keys, not Claude-named |
| G-23 | Stress harness Grok path | Low priority unless load-testing ACP providers |
| G-24 | MCP Settings copy for Grok (commands / prompts dirs) | Only if Grok has analogous dirs |
| G-25 | `claude-rp` analogue wrapper | Product decision; likely not needed if Agent Mode inject is primary |

### P3 / Class A — Do not treat as Grok deficits

| ID | Item | Reason |
| --- | --- | --- |
| A-01 | Codex app-server, steer-ack, goal/computer-use | Different protocol |
| A-02 | Claude plugin package / compatible backends (GLM/Kimi) | Different product family |
| A-03 | Claude prompt-delivery modes / system-prompt replace | Claude CLI flags |
| A-04 | Codex service tiers / reasoning summaries | Codex model product |
| A-05 | Port Claude/Codex native coordinators to Grok | Grok uses shared ACP plane by design |
| A-06 | Store xAI API keys under Grok Build | Auth is `grok login`; HTTP Grok remains separate |

---

## 6. Fairer peer: Cursor / OpenCode vs Grok

Planning target is **Cursor ACP parity**. Rough peer check:

| Peer feature | Cursor | OpenCode | Grok | Comment |
| --- | --- | --- | --- | --- |
| ACP agent + headless + CLIProvider | Y | Y | Y | Aligned |
| Model polling | Y | Y | Y | Aligned |
| Default/Full Access prefs | Y | Session mode | Y (like Cursor) | Aligned with Cursor |
| IntegrationConfiguration | Project MCP approval | Ephemeral ACP config | **N** | Main peer gap if Grok needs host-side MCP config files |
| Recommendation status | Partial (in snapshot) | Often off | **Worse** (enum only) | Grok below Cursor |
| MCP grant policy | Shared with Grok | Own set | = Cursor | Intentional clone |
| Pre-prompt MCP routing | Off | On | Off | Matches Cursor |

**Conclusion:** Protocol/core Agent Mode for Grok is near Cursor. Largest remaining gaps are **recommendation/onboarding wiring** and optional **integration config**, not a missing ACP stack.

---

## 7. Suggested sequencing (if continuing polish)

1. **Fix recommendation plumbing (G-01, G-02, G-10–G-13)** — makes Connect Grok visible to wizards and defaults without new protocols.
2. **Startup probe parity (G-17)** — reduces stale connected flags.
3. **Tests (G-14)** — lock effort + MCP identity + Oracle raw IDs.
4. **Product policy** — Best Practice placement of Grok (G-12), release changelog (G-20).
5. **Evaluate G-15/G-16** only with evidence from real Grok MCP/config docs and user workflows.
6. **Never** expand scope into A-01…A-06 unless product explicitly re-targets architecture.

---

## 8. Evidence sources (code)

| Topic | Path |
| --- | --- |
| Provider kinds / MCP hints / ACP ids | `Features/AgentMode/Runtime/Providers/AgentRuntimeProviderService.swift` |
| Catalog + selectable agents | `Features/AgentMode/Models/ModelSelection/AgentModelCatalog.swift` |
| Recommendations (Grok stub) | `Features/AgentMode/Recommendations/RecommendationTypes.swift`, `AutoRecommendationEngine.swift` |
| Connect + status snapshot | `Features/Settings/ViewModels/APISettingsViewModel.swift` |
| CLI Providers UI | `Features/Settings/Views/CLIProvidersSettingsView.swift` |
| Permission UI tool panel exclusion | `Features/Settings/Views/AgentProviderPermissionControlsComponents.swift` |
| MCP tool grants | `Infrastructure/MCP/Policies/AgentModeMCPToolPolicy.swift` |
| MCP identity | `Infrastructure/MCP/MCPClientIdentity.swift` |
| Grok stack | `Infrastructure/AI/Providers/GrokBuild/*` |
| Claude package seam | `docs/architecture/provider-plugins.md` |
| Live Oracle smoke | [Phase3-oracle-smoke.md](./Phase3-oracle-smoke.md) |

---

## 9. One-line summary

**Grok Build has core Agent Mode + Oracle wiring at Cursor-ACP depth; vs Codex/Claude it intentionally lacks native-runtime features, but still has clear product gaps where recommendation/onboarding and status plumbing treat Grok as a stub (`grokBuildAvailable: false`, no status field) despite Connect and live smokes succeeding.**
