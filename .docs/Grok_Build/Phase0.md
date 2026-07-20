# Phase 0 — ACP Probe Checklist + AgentProviderKind Wiring Inventory

**Status:** Pre-implementation (still **no code changes**)
**Date:** 2026-07-20
**Parent plan:** [Planning.md](./Planning.md)
**Naming note:** This file is the Phase 0 investigation gate that unlocks Phase 1 MVP coding.

This document has two parts:

1. **ACP probe checklist** — evidence to gather against live `grok` before writing product code.
2. **Wiring inventory** — every CE surface that must learn about a new Cursor-like ACP provider (`AgentProviderKind` / `ACPProviderID` / bindings / UI / tests).

---

## Part A — ACP probe checklist

### A.0 Probe environment

Record once per machine used for evidence:

| Field | Record |
| --- | --- |
| Date / operator | |
| Host OS | e.g. macOS 26.x arm64 |
| `which -a grok` (interactive) | |
| `/bin/zsh -lc 'which -a grok; grok --version'` (login shell ≈ App) | |
| `grok --version` | |
| Auth (`grok login` status / “logged in with grok.com”) | |
| RepoPrompt under test | `/Applications/RepoPrompt CE.app` and/or debug build |
| Workspace path used for session/new | |

**Pass rule for A.0:** login-shell resolution finds a single preferred `grok` ≥ minimum version decided in A.2; auth is logged in.

---

### A.1 Launch surface

| ID | Probe | Method | Pass criteria | Result (fill) | Evidence path |
| --- | --- | --- | --- | --- | --- |
| L1 | Help advertises agent stdio | `grok agent --help`, `grok agent stdio --help` | Documents stdio ACP mode | | |
| L2 | Process stays up on stdio | Spawn `grok agent stdio` (optionally with `-m <model>` **before** `stdio`) | Process waits on stdin; no immediate exit | | |
| L3 | Flag order | Compare `grok agent -m <model> stdio` vs `grok agent stdio -m …` | Document working order for resolver | | |
| L4 | Always-approve flag | `grok agent --always-approve stdio` (and aliases if any) | Process starts; note security implications for headless | | |
| L5 | Working directory | Start with cwd = workspace root | Relative tools resolve under workspace | | |
| L6 | Env inheritance | Strip PATH to minimal; only supplemental dirs | Document required PATH entries for GUI App | | |
| L7 | Binary identity | Resolve symlink targets under `~/.local/bin` / `~/.grok/bin` | Absolute path stable for `ExecutableFileIdentity` | | |

**Cursor reference:** `CursorACPLaunchCandidate` uses `cursor-agent --approve-mcps acp` + `acp --help` preflight.
**Grok expected:** primary candidate `["agent", "stdio"]` with model flags on `agent` parent (confirm L3).

---

### A.2 Version / support preflight

| ID | Probe | Method | Pass criteria | Result | Evidence |
| --- | --- | --- | --- | --- | --- |
| V1 | Version parse | `grok --version` / `grok version` | Machine-readable or stable human string | | |
| V2 | ACP advertisement | Help text contains ACP / agent client protocol / stdio agent | Suitable for Connect preflight like Cursor’s help check | | |
| V3 | Minimum version policy | Compare known-good local version | Freeze “min version” message for Connect failures | | |
| V4 | Stale binary behavior | If a second old `grok` exists, prefer wrong PATH | Confirms need for path display + hints (Codex lesson) | | |

---

### A.3 Authentication

| ID | Probe | Method | Pass criteria | Result | Evidence |
| --- | --- | --- | --- | --- | --- |
| A1 | Logged-in happy path | With valid grok.com session, run L2 + initialize | Initialize succeeds | | |
| A2 | Logged-out path | `grok logout` (or temp HOME), retry initialize/prompt | Clear error; CE must map to “run `grok login`” | | |
| A3 | Auth vs executable errors | Rename/remove binary vs logout | Distinct messages; not one collapsed string | | |
| A4 | No dependency on xAI API key in Keychain | Disconnect CE `AIProviderType.grok` key if set | ACP still works with CLI login only | | |
| A5 | Reauth flag | `grok agent --reauth stdio` behavior | Document whether CE should ever pass it | | |

---

### A.4 ACP protocol lifecycle (stdio JSON-RPC)

Use a small script or existing CE ACP client harness. Prefer newline-delimited JSON-RPC matching `ACPAgentSessionController` expectations (compare with OpenCode/Cursor wire logs if available).

| ID | Probe | Request / observation | Pass criteria | Result | Evidence |
| --- | --- | --- | --- | --- | --- |
| P1 | `initialize` | Client capabilities + clientInfo | Result with agent capabilities; note protocol version | | |
| P2 | Initialized / session setup | Follow CE’s OpenCode/Cursor sequence exactly | No hang; ready for session/new | | |
| P3 | `session/new` | cwd = workspace | Returns session id | | |
| P4 | `session/prompt` | Short user message (“Reply with PONG only”) | Streamed updates; final stop reason | | |
| P5 | `session/update` types | Observe thought / message / tool_call | Map to CE transcript/tool cards | | |
| P6 | Permission request | Prompt that needs a write or shell tool **without** always-approve | CE-shaped approval request appears | | |
| P7 | Permission deny | Deny once | Agent continues or errors gracefully; no deadlock | | |
| P8 | Permission allow | Allow once | Tool completes; tool_call_update seen | | |
| P9 | Cancel / interrupt | Mid-turn cancel if CE/Grok support it | Transport reusable or cleanly restarted | | |
| P10 | `session/load` or resume | Use prior session id if advertised | Document load confidence (verified vs candidate) | | |
| P11 | Second turn same session | Follow-up prompt | Context retained | | |
| P12 | Invalid method | Send unknown method | JSON-RPC error; process survives | | |
| P13 | Malformed line | Inject bad JSON | Recovery or clean exit; note CE decode policy | | |
| P14 | Extension methods | List any `x.ai/*` required for basic chat | MVP must not depend on extensions unless mandatory | | |

**Pass rule for Part A.4:** P1–P5 and P11 required for Phase 1. P6–P8 required if Agent Mode permissions are in MVP (yes for Cursor parity). P10 documents resume policy even if “unsupported”.

---

### A.5 Models and effort

| ID | Probe | Method | Pass criteria | Result | Evidence |
| --- | --- | --- | --- | --- | --- |
| M1 | CLI model list | `grok models` | Non-empty list; default marked | | |
| M2 | ACP model list / set | If session methods expose models | Document method names and raw ids | | |
| M3 | Launch with `-m` | `grok agent -m <id> stdio` then prompt | Uses requested model or clear error | | |
| M4 | Raw value stability | Note ids (`grok-4.5`, etc.) | Safe for `AgentModel` persistence | | |
| M5 | Effort / reasoning | `--reasoning-effort` / ACP fields | Whether CE needs effort UI in Phase 1 | | |
| M6 | Unknown model | Pass bogus model id | Clear error | | |

---

### A.6 MCP (RepoPrompt server)

Goal: Cursor-parity — agent can call RepoPrompt MCP tools from Agent Mode.

| ID | Probe | Method | Pass criteria | Result | Evidence |
| --- | --- | --- | --- | --- | --- |
| C1 | Session mcpServers | Pass RepoPrompt MCP in `session/new` (CE shape) | Server listed / tools available | | |
| C2 | Config.toml inject | Temporary `[mcp_servers.repoprompt]` in `~/.grok` or project | Tools available if C1 fails | | |
| C3 | Project-local vs global | Project-scoped config if Grok supports it | Prefer non-destructive project prep + cleanup (Cursor pattern) | | |
| C4 | Tool call to RP tool | e.g. windows / tree via MCP | Tool card + result in session | | |
| C5 | Permission on MCP tool | If elicitation/approval required | Maps to CE approval or auto-approve policy | | |
| C6 | Timeout | Long-running MCP | Document whether timeout is configurable (do not invent) | | |
| C7 | Cleanup | After run, remove project MCP approval artifacts if created | No leftover trusted-server state unless intended | | |

**Cursor reference:** `CursorIntegrationConfiguration.prepareProjectMCPApproval` + `CURSOR_DATA_DIR` + `--approve-mcps`.
**Grok:** choose **one** authoritative inject path from C1–C3; record rejected alternatives.

---

### A.7 Headless (Phase 2 gate; optional evidence now)

| ID | Probe | Method | Pass criteria | Result | Evidence |
| --- | --- | --- | --- | --- | --- |
| H1 | Single prompt | `grok -p "Reply PONG" --output-format plain` | Prints and exits 0 | | |
| H2 | Streaming JSON | `--output-format streaming-json` | Parseable events | | |
| H3 | Tools in headless | Prompt requiring read_file | Works with `--yolo` / allow rules | | |
| H4 | Comparison | ACP vs `-p` for discovery | Decide Phase 2 provider shape | | |

---

### A.8 Failure matrix (Connect message design)

Fill expected CE user-facing message **per class** (do not collapse):

| Class | How to induce | Desired CE message theme | Cursor/OpenCode analogue |
| --- | --- | --- | --- |
| Not installed | Empty PATH | Install Grok Build; open docs URL | Cursor missing CLI |
| Found but not executable | chmod -x | Permission / not executable | |
| Wrong/old binary | Fake older stub | Upgrade Grok Build CLI | |
| Not authenticated | logout | Run `grok login`, then Connect | |
| ACP unsupported | stub binary | CLI lacks agent stdio ACP | Cursor acp --help fail |
| MCP prep failed | unwritable project dir | MCP setup failed (detail) | Cursor MCP approval |
| Initialize timeout | block process | Timed out talking to Grok ACP | |
| Transport crash mid-prompt | kill -9 child | Session ended; retry | |

---

### A.9 Phase 0 exit criteria (gate for coding)

Phase 1 implementation may start only when:

- [x] L2 + P1–P5 pass on login-shell-resolved `grok`
- [x] A1/A2 distinguish auth vs missing binary *(A2 not destructively logged out; design accepted — see evidence)*
- [x] Launch argv frozen (write into plan “Frozen decisions” below)
- [x] MCP inject path chosen (C1 session `mcpServers` / CE shape); **real RepoPrompt tool call deferred** to Phase 1 live validation
- [x] Permission path: host is always-approve; CE approval path still required; re-probe later without always-approve
- [x] Model raw ids listed for initial catalog (`grok-4.5`)
- [x] Evidence notes stored under `.docs/Grok_Build/Phase0-evidence.md`

**Gate status (2026-07-20): OPEN for Phase 1 MVP coding.**

### A.10 Frozen decisions (filled 2026-07-20 — see Phase0-evidence.md)

| Decision | Value | Date |
| --- | --- | --- |
| `AgentProviderKind` raw | `grokBuild` | 2026-07-20 |
| `ACPProviderID` / binding | `grokBuild` | 2026-07-20 |
| Launch command | `grok` | 2026-07-20 |
| Launch arguments | `agent stdio`; model via `agent -m <id> stdio` (**before** `stdio`) | 2026-07-20 |
| Min CLI version | Known-good `0.2.106`; require working `agent stdio` | 2026-07-20 |
| Auth check | ACP `authenticate` + `cached_token`; fallback `grok models` “logged in”; user action `grok login` | 2026-07-20 |
| MCP inject strategy | **session** `mcpServers` using CE `acpJSONObject` (`type: stdio`, …) | 2026-07-20 |
| Headless strategy (Phase 2) | `grok -p` / streaming-json; interactive remains ACP | 2026-07-20 |
| MCP server name | `RepoPromptCE` (existing CE default) | 2026-07-20 |
| Default model raw | `grok-4.5` | 2026-07-20 |

---

## Part B — AgentProviderKind / Cursor-parity wiring inventory

Use this as a **touch list** when implementing Phase 1. Mirror **Cursor** first; OpenCode only where Cursor is incomplete.

Legend: **R** = required for MVP compile+Connect+Agent Mode · **S** = strongly recommended parity · **L** = later (Phase 2+) · **T** = tests

### B.1 New source files (proposed)

| Path | Role | Priority |
| --- | --- | --- |
| `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/GrokBuildAgentConfig.swift` | Config (command, hints, model, MCP flags) | R |
| `.../GrokBuildACPLaunchResolver.swift` | PATH resolve, preflight, cache | R |
| `.../GrokBuildACPAgentProvider.swift` | `ACPAgentProvider` conformance | R |
| `.../GrokBuildIntegrationConfiguration.swift` | MCP project prep/cleanup if needed | R if C2/C3 |
| `.../GrokBuildAgentToolPreferences.swift` | Permission levels | R |
| `.../GrokBuildCLIProvider.swift` | Connect/test helpers if not only in ViewModel | S |
| `.../GrokBuildACPModelPollingService.swift` | Live model discovery | S (MVP if Connect shows models) |
| `.../GrokBuildACPHeadlessAgentProvider.swift` | Headless | L |
| `.../GrokBuildACPEventNormalizer.swift` | Only if event shape differs | L / if needed |
| `Tests/RepoPromptTests/AgentMode/GrokBuildACPLaunchResolverTests.swift` | Resolver contract | T |
| Additional focused tests for factory/binding/catalog | | T |

**Do not create:** `Packages/RepoPromptAgentProviders/...Grok...` for MVP.
**Do not modify:** Claude-compatible package product for Grok Build.
**Do not repurpose:** `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokProvider.swift` (xAI HTTP).

### B.2 Core enums and provider identity (exhaustive switches)

| File | What to add | Priority |
| --- | --- | --- |
| `Features/AgentMode/Runtime/Providers/AgentRuntimeProviderService.swift` | `AgentProviderKind.grokBuild`; `commandName`, `displayName`, `mcpClientNameHint`, `acpProviderID`, flags, `agentDescription`, `runtimeKind`, `makeProvider` branch | R |
| `Features/AgentMode/Providers/ACP/ACPAgentProvider.swift` | `ACPProviderID.grokBuild` | R |
| `Infrastructure/AI/ACP/ACPAgentProviderFactory.swift` | `case .grokBuild: GrokBuildACPAgentProvider(...)` | R |
| `Features/AgentMode/Runtime/ProviderBindings/AgentProviderBindingID.swift` | `case grokBuild` + `AgentProviderKind.providerBindingID` | R |
| `Features/AgentMode/Runtime/ProviderBindings/AgentProviderBindingModels.swift` | Permission level case for Grok Build | R |
| `Features/AgentMode/Runtime/ProviderBindings/AgentPermissionSecureStore.swift` | Document kind / encode-decode branch | R |
| `Features/AgentMode/Runtime/ProviderBindings/AgentProviderPermissionProfile.swift` | Capability / default profile | R |
| `Features/AgentMode/Runtime/ProviderBindings/AgentProviderPreferenceSnapshotStore.swift` | Snapshot load/save | R |
| `Features/AgentMode/Runtime/ProviderBindings/AgentModeProviderBindingService.swift` | Binding assembly | R |
| `Infrastructure/Process/CLILaunchProfile.swift` | `CLILaunchProfiles.grokBuild` + supplemental paths (`~/.local/bin`, `~/.grok/bin`, …) | R |
| `Infrastructure/AI/Providers/CLIPathHints.swift` (if used by Cursor) | Grok Build hints | R |
| `Infrastructure/Telemetry/SentryTelemetryModel.swift` | Provider labels if exhaustive | S |
| `Infrastructure/Security/SecureStorageAccountCatalog.swift` | Only if CE stores a Grok Build–specific secret account | L / if needed |
| `Infrastructure/AI/Providers/AIProviderFactory.swift` | **Avoid** conflating with `AIProviderType.grok` | — |

### B.3 ACP runtime and Agent Mode

| File | What to add | Priority |
| --- | --- | --- |
| `Features/AgentMode/Runtime/Runners/ACPIntegratedAgentModeRunner.swift` | Ensure provider-agnostic; fix any hard-coded openCode/cursor assumptions | R |
| `Infrastructure/AI/ACP/ACPAgentSessionController.swift` | Only if Grok violates shared assumptions (modes, load id) | S |
| `Infrastructure/AI/ACP/ACPProviderSupport.swift` | Support matrix helpers if present | S |
| `Infrastructure/AI/Providers/ACPHeadlessAgentProviderBridge.swift` | Headless bridge branch | L |
| `Infrastructure/AI/Providers/ACPHeadlessProviderLifecycle.swift` | Lifecycle | L |
| `Infrastructure/AI/Providers/ACPLaunchEnvironmentDiagnostics.swift` | Diagnostics copy | S |
| `Features/AgentMode/ViewModels/AgentModeViewModel.swift` | Availability, runner selection, any kind switches | R |
| `Features/AgentMode/ViewModels/AgentModeViewModel+ContextUsage.swift` | If kind-switched | S |
| `Features/AgentMode/Runtime/Transcript/AgentToolResultPersistencePolicy.swift` | If provider-specific | S |
| `Features/AgentMode/Runtime/AgentSkillCatalog.swift` | If provider-gated skills | L |
| `Infrastructure/MCP/Agent/AgentRunSessionStore.swift` | Session metadata kind | S |
| `Infrastructure/MCP/Policies/AgentModeMCPToolPolicy.swift` | Client id / policy | S |
| `Infrastructure/MCP/MCPIntegrationHelper.swift` | Install/discovery helpers if needed | S |
| `Infrastructure/MCP/AppSettingsMCPService.swift` | Settings exposure if kind-listed | S |

### B.4 Model catalog and AI model types

| File | What to add | Priority |
| --- | --- | --- |
| `Features/AgentMode/Models/ModelSelection/AgentModel.swift` | Default/static Grok Build models if CE owns raws | R |
| `Features/AgentMode/Models/ModelSelection/AgentModelCatalog.swift` | Options / defaults / validation for `.grokBuild` | R |
| `Infrastructure/AI/ModelCatalog/Providers/ACPAIModelCatalog.swift` | ACP discovery mapping | S |
| `Infrastructure/AI/AIModel.swift` | Only if chat picker shares models (usually **not** for CLI agents) | L |
| `Features/Settings/Views/AIModelDropDown.swift` | If Agent Mode menus need grouping | S |

### B.5 Settings / CLI Providers UI (Cursor card parity)

| File | What to add | Priority |
| --- | --- | --- |
| `Features/Settings/Views/CLIProvidersSettingsView.swift` | Grok Build card: Connect, Sign out, errors, model summary | R |
| `Features/Settings/ViewModels/APISettingsViewModel.swift` | `isGrokBuildConnected`, errors, test connection, polling hooks, context-builder verified flags | R |
| `Features/Settings/Views/AgentModeGeneralSettingsView.swift` | Provider lists if exhaustive | S |
| `Features/Settings/Views/AgentProviderPermissionControlsComponents.swift` | Permission controls for binding | R |
| `Features/AgentMode/ViewModels/UI/AgentProviderPermissionsSettingsViewModel.swift` | Binding VM | R |
| `Features/AgentMode/ViewModels/UI/AgentPermissionCapabilitySummaryBuilder.swift` | Summaries | S |
| `Features/AgentMode/ViewModels/UI/AgentRuntimeSidebarViewModel.swift` | Sidebar provider chrome | S |
| `App/Notifications/WorkspaceNotifications.swift` | e.g. `grokBuildConnectionChanged` | R |
| `App/WindowStateManager.swift` | Shutdown model polling on terminate | S |
| `App/Changelog.swift` | User-facing note when shipping | L (ship PR) |

### B.6 Recommendations / onboarding / prompt availability

| File | What to add | Priority |
| --- | --- | --- |
| `Features/AgentMode/Recommendations/RecommendationTypes.swift` | Provider case if needed | L |
| `Features/AgentMode/Recommendations/AutoRecommendationEngine.swift` | Ranking | L |
| `Features/AgentMode/ViewModels/Recommendations/RecommendationWizardViewModel.swift` | Wizard | L |
| `Features/AgentMode/ViewModels/Onboarding/AgentOnboardingWizardViewModel.swift` | Onboarding | L |
| `Features/Prompt/ViewModels/PromptViewModel.swift` | Availability refresh keys | S |
| `Features/ContextBuilder/ViewModels/ContextBuilderAgentViewModel.swift` | Verified provider wiring | S |
| `Infrastructure/WorkspaceContext/WorkspaceFileContextStore.swift` | If provider-gated | L |

### B.7 Tests inventory (Cursor/OpenCode analogues)

| Existing test / area | Grok Build action | Priority |
| --- | --- | --- |
| `Tests/RepoPromptTests/AgentMode/CursorACPLaunchResolverTests.swift` | Clone patterns for GrokBuild resolver | T |
| `Tests/RepoPromptTests/AgentMode/OpenCodeACPLaunchResolverTests.swift` | PATH / supplemental path patterns | T |
| `Tests/RepoPromptTests/AgentMode/ACPProviderSessionIdentityTests.swift` | New providerID cases if exhaustive | T |
| `Tests/RepoPromptTests/AgentMode/ACPAgentSessionControllerModeConfigTests.swift` | Only if mode config differs | T |
| `Tests/RepoPromptTests/AgentMode/ACPSynchronousMCPStartupTests.swift` | MCP startup if inject path needs it | T |
| `Tests/RepoPromptTests/Prompt/PromptAgentAvailabilityRefreshTests.swift` | Connected key list | T |
| `Tests/RepoPromptTests/ContextBuilder/ContextBuilderModelStartupSelectionTests.swift` | Connected keys | T |
| `Tests/RepoPromptTests/SettingsJSONOnlyPersistenceTests.swift` | If settings keys added | T |
| `Tests/RepoPromptTests/Security/SecureStorageAccountCatalogTests.swift` | If new secure accounts | T |
| Permission secure store tests | New binding document | T |
| Exhaustive switch compile | Any `switch` on `AgentProviderKind` / `ACPProviderID` / binding | T (compiler-enforced) |

### B.8 Documentation (product / architecture)

| Path | Action | Priority |
| --- | --- | --- |
| `docs/architecture/provider-plugins.md` | Note Grok Build as ACP example (optional) | L |
| `.docs/Grok_Build/Phase0-evidence.md` | Fill after probes | R before coding |
| User-facing help / README | Install `grok`, login, Connect | L |

### B.9 Cursor file → Grok Build mapping (quick index)

| Cursor (source of truth for parity) | Grok Build target |
| --- | --- |
| `CursorAgentConfig.swift` | `GrokBuildAgentConfig.swift` |
| `CursorACPLaunchResolver.swift` | `GrokBuildACPLaunchResolver.swift` |
| `CursorACPAgentProvider.swift` | `GrokBuildACPAgentProvider.swift` |
| `CursorACPHeadlessAgentProvider.swift` | Phase 2 |
| `CursorACPModelPollingService.swift` | `GrokBuildACPModelPollingService.swift` |
| `CursorIntegrationConfiguration.swift` | `GrokBuildIntegrationConfiguration.swift` |
| `CursorCLIProvider.swift` | Optional |
| `CursorAgentToolPreferences.swift` | `GrokBuildAgentToolPreferences.swift` |
| `CursorACPEventNormalizer.swift` | Only if needed |
| CLI Providers `cursorCard` | `grokBuildCard` |
| `APISettingsViewModel` cursor connection API | Grok Build connection API |
| `ACPAgentProviderFactory` `.cursor` | `.grokBuild` |
| `AgentProviderBindingID.cursor` | `.grokBuild` |

### B.10 Explicit non-touch (MVP)

| Area | Reason |
| --- | --- |
| `RepoPromptClaudeCompatibleProvider` package | Wrong protocol family |
| `CodexAppServerClient` / managed ChatGPT auth | Wrong auth and transport |
| `GrokProvider` / `AIProviderType.grok` API chat | Different product (HTTP xAI); keep working independently |
| Dynamic plugin loading | Seam is static SwiftPM composition only |
| Force-push / destructive git | N/A to this feature |

---

## Part C — Suggested Phase 0 execution order (still no app code)

1. Fill A.0 environment table on the machine with `/Applications/RepoPrompt CE.app`.
2. Run L1–L7 and V1–V3; fix local PATH issues if login shell cannot find `grok`.
3. Script P1–P5 against `grok agent stdio`; capture raw JSON-RPC transcript.
4. Run A1–A4 auth matrix.
5. Run C1 then C2; pick MCP strategy.
6. Run P6–P8 permission matrix.
7. Fill A.10 frozen decisions.
8. Open implementation issue / PR plan referencing Planning.md + this file.
9. Only then start B.1–B.5 coding in a dedicated branch.

---

## Part D — Maintainer-guidance check (Phase 0)

| Item | Assessment |
| --- | --- |
| **User impact and invariant** | Evidence that Cursor-like Grok Build ACP is implementable without false auth paths. |
| **Root-cause confidence** | Architecture fit **confirmed**; wire-level details **unknown** until probes complete. |
| **Authority** | Live Grok CLI ACP + existing CE ACP controller; Cursor code as structural template. |
| **State-safety risks** | None until enums land; freeze raw values in A.10 before first commit. |
| **Scale and observability risks** | Probe scripts must not thrash user `~/.grok` config; prefer project-scoped MCP prep with cleanup. |
| **Recommended scope** | Complete Part A before any `AgentProviderKind` change. |
| **Validation boundary** | Login-shell `grok` + stdio ACP transcript + one MCP tool (or documented deferral). |
