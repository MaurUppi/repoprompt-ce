# Grok Build Support — Overall Plan (ACP Provider)

**Status:** Planning (no implementation in this document)
**Date:** 2026-07-20
**Goal:** Add Grok Build as a first-class Agent Mode / CLI Provider in RepoPrompt CE, at parity with **Cursor CLI** (ACP-based), not as a Claude-compatible backend and not as the existing xAI HTTP `GrokProvider`.
**Authority docs:** `docs/architecture/provider-plugins.md`, Cursor/OpenCode ACP implementations under `Sources/RepoPrompt/Infrastructure/AI/Providers/{Cursor,OpenCode}/`
**Related investigation notes:** Codex Connect PATH split (login-shell vs interactive) — apply the same lessons to `grok` resolution under `/Applications/RepoPrompt CE.app`.

---

## 1. User impact and invariant

### Observable user impact

After Connect, a user can:

1. See **Grok Build** in **Settings → CLI Providers** (alongside Claude Code, Codex, OpenCode, Cursor).
2. **Connect** successfully when the Grok Build CLI (`grok`) is installed, on PATH for login-shell resolution, and authenticated (`grok login` / grok.com).
3. Select Grok Build models in **Agent Mode**, run multi-turn sessions with tool cards, permission prompts, and **RepoPrompt MCP** tools.
4. Use the same operational loop as Cursor: Connect → pick model → Agent Mode chat / agent_run via MCP.

### Invariants

| Invariant | Meaning |
| --- | --- |
| One runtime shape | Grok Build interactive Agent Mode uses **ACP over stdio** (`grok agent stdio`), same control plane as OpenCode/Cursor. |
| One authority for protocol | Wire protocol and session lifecycle come from **Grok’s ACP implementation** + RPCE’s `ACPAgentSessionController`; do not invent a parallel RPC. |
| Name isolation | **Grok Build (CLI/ACP)** ≠ existing **Grok (xAI) OpenAI-compatible API** (`GrokProvider` / `AIProviderType.grok`). |
| Credential isolation | Grok Build auth lives with the Grok CLI (`~/.grok`, `grok login`). Do not reuse Codex ChatGPT, Claude, or xAI API key Keychain entries for Connect. |
| Stable raw values | New `AgentProviderKind` / binding / UserDefaults keys are durable once shipped; plan names before first commit. |
| No false auth errors | Connect failures must surface real causes (PATH, wrong binary, version, login, ACP preflight). Do not collapse process/RPC failures into a single “re-login” string (Codex lesson). |

---

## 2. Why ACP (and not other seams)

From `docs/architecture/provider-plugins.md`:

| Runtime shape | RPCE pattern | Grok Build fit |
| --- | --- | --- |
| Claude-compatible package plugin | `RepoPromptClaudeCompatibleProvider` + adapter trio | **No** — not Claude SDK/NDJSON. |
| Codex app-server | `CodexAppServerClient` / native session controller | **No** — different RPC surface. |
| **ACP** | `ACPAgentProvider` + `ACPAgentSessionController` + `ACPIntegratedAgentModeRunner` | **Yes** — Grok documents `grok agent stdio` as ACP JSON-RPC for IDEs. |
| Headless CLI | `HeadlessAgentProvider` | **Secondary** — `grok -p` / `--output-format streaming-json` for discovery/delegate, Cursor-like optional path. |

**Decision:** Implement Grok Build as the **third ACP family** after OpenCode and Cursor, copying Cursor’s layering and product surface as the primary template.

---

## 3. Upstream surface (authoritative)

| Surface | Command / location | Role in RPCE |
| --- | --- | --- |
| Interactive ACP | `grok agent stdio` (options on `grok agent`, e.g. `-m`, `--always-approve`) | Primary Agent Mode transport |
| Auth | `grok login` / `grok logout` / local grok.com session | Connect preflight |
| Models | `grok models` | Catalog / polling seed |
| Headless | `grok -p "…"` + `--output-format plain\|json\|streaming-json` | Optional headless provider |
| MCP | `grok mcp` + `~/.grok/config.toml` `[mcp_servers.*]` | May need project-scoped or env injection like Cursor |
| Config home | `~/.grok/` | PATH, credentials, plugins — not RepoPrompt App Support |
| Binary locations (typical) | `~/.local/bin/grok`, `~/.grok/bin/grok` | Launch resolver + supplemental PATH hints |

Phase 0 must **probe** exact initialize/session/prompt/permission/MCP behavior before freezing launch args and session config (see `Phase0.md`).

---

## 4. Naming (avoid collision with existing Grok API provider)

| Concept | Proposed name | Notes |
| --- | --- | --- |
| UI label | **Grok Build** | Matches product |
| `AgentProviderKind` | `grokBuild` (raw `"grokBuild"`) | Distinct from chat API |
| `ACPProviderID` | `grokBuild` | Exhaustive switches today only `openCode` / `cursor` |
| `AgentProviderBindingID` | `grokBuild` | Own permission document group |
| CLI command | `grok` | Prefer basenames `["grok"]` |
| Connect defaults key | e.g. `GrokBuildCLIConnected` | Mirror `CursorCLIConnected` |
| Source folder | `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/` | Not `Grok/` (HTTP provider lives as `GrokProvider.swift`) |
| MCP client hint | e.g. `grok` or `grok-build` | Confirm against Grok MCP identity in Phase 0 |
| Telemetry | New cases on Sentry provider enums | Do not overload `.grok` HTTP if already used |

**Do not** repurpose `AIProviderType.grok` / `GrokProvider` (OpenAI-compatible xAI API) for Agent Mode CLI.

---

## 5. Target architecture (Cursor-shaped)

```
Settings / CLI Providers (Connect, models, permissions)
        │
        ▼
APISettingsViewModel ── probe launch + auth + optional model poll
        │
        ▼
Agent Mode selection (AgentProviderKind.grokBuild)
        │
        ├─ Interactive: ACPAgentProviderFactory
        │       → GrokBuildACPAgentProvider : ACPAgentProvider
        │       → ACPLaunchConfiguration (command/args/env/cwd)
        │       → ACPSessionConfiguration (session/new|load + MCP servers)
        │       → ACPAgentSessionController (shared)
        │       → ACPIntegratedAgentModeRunner (shared)
        │
        └─ Headless (phase 2+): GrokBuildACPHeadlessAgentProvider
                → AgentRuntimeProviderService.makeProvider(...)
```

Shared core (reuse, do not fork):

- `Sources/RepoPrompt/Features/AgentMode/Providers/ACP/ACPAgentProvider.swift`
- `Sources/RepoPrompt/Infrastructure/AI/ACP/ACPAgentSessionController.swift`
- `Sources/RepoPrompt/Features/AgentMode/Runtime/Runners/ACPIntegratedAgentModeRunner.swift`
- `ACPPromptContentBuilder`, launch environment diagnostics, MCP bootstrap paths used by Cursor/OpenCode

Grok-specific (new, mirror Cursor):

| Cursor file | Grok Build analogue |
| --- | --- |
| `CursorAgentConfig.swift` | `GrokBuildAgentConfig.swift` |
| `CursorACPLaunchResolver.swift` | `GrokBuildACPLaunchResolver.swift` |
| `CursorACPAgentProvider.swift` | `GrokBuildACPAgentProvider.swift` |
| `CursorACPHeadlessAgentProvider.swift` | `GrokBuildACPHeadlessAgentProvider.swift` (later) |
| `CursorACPModelPollingService.swift` | `GrokBuildACPModelPollingService.swift` |
| `CursorACPEventNormalizer.swift` | Only if Grok events need normalization |
| `CursorIntegrationConfiguration.swift` | MCP approval / project config if required |
| `CursorCLIProvider.swift` | Optional thin Connect/test helper |
| `CursorAgentToolPreferences.swift` | `GrokBuildAgentToolPreferences.swift` |

**Not in scope for the Claude package seam:** no new `RepoPromptGrokProvider` product under `Packages/RepoPromptAgentProviders` for MVP. Revisit only if a large pure codec grows outside ACP.

---

## 6. Phased delivery

### Phase 0 — Investigation / ACP spike (no product wiring)

**Output:** `.docs/Grok_Build/Phase0.md` (probe + wiring inventory), then evidence notes under `.docs/Grok_Build/` or `docs/investigations/` as needed.

- Manual / scripted ACP stdio probe against local `grok agent stdio`.
- Confirm auth, model list, permission, MCP inject, resume/load, error shapes.
- Freeze launch argv, env, and Connect success criteria.
- **Gate:** no `AgentProviderKind` commit until probe checklist is filled with pass/fail evidence.

Details: **[Phase0.md](./Phase0.md)**.

### Phase 1 — MVP (Cursor-parity core path)

Ship the smallest complete path:

1. **Launch + Connect**
   - Login-shell-aware PATH resolution with supplemental hints (`~/.local/bin`, `~/.grok/bin`, …).
   - Preflight: executable + `agent stdio` help/version + **auth status** (explicit, not collapsed).
   - CLI Providers card: Connect / Sign out / error text / optional model summary.
2. **ACP interactive Agent Mode**
   - `ACPProviderID.grokBuild` + `GrokBuildACPAgentProvider`.
   - Factory + runner branch.
   - Session new/load, prompt streaming, tool cards, permission UI via existing binding stack.
3. **RepoPrompt MCP injection**
   - Same product goal as Cursor: agent can call RepoPrompt MCP tools in Agent Mode.
   - Mechanism chosen from Phase 0 (session `mcpServers` vs config.toml vs env) — prefer the path Grok actually honors.
4. **Model catalog minimum**
   - Static defaults + discovered models from polling or session metadata.
   - Persisted `AgentModel` raw values stable from day one.
5. **Permissions binding**
   - New `AgentProviderBindingID.grokBuild` + secure store document + settings UI controls (mirror Cursor depth as far as Grok exposes levels).
6. **Tests**
   - Launch resolver unit tests (PATH order, absolute path, reject unsafe paths).
   - Factory/kind exhaustiveness compilation.
   - Focused ACP session tests with fakes where Cursor/OpenCode already pattern them.
7. **Validation**
   - `make dev-swift-build PRODUCT=RepoPrompt`
   - Focused tests for new suites
   - Live: `/Applications` or debug app Connect + one Agent Mode turn with MCP tool if credentials available

**Explicit non-goals for Phase 1:** recommendations wizard polish, full headless parity, `x.ai/*` ACP extensions, Claude plugin package, changing existing `GrokProvider` API chat path.

### Phase 2 — Headless + discovery parity

- `GrokBuildACPHeadlessAgentProvider` (or headless via `grok -p` if ACP headless is weaker).
- Model polling service lifecycle in `WindowStateManager` (start/stop with connection).
- Context Builder / Prompt availability refresh keys.
- Richer catalog menus, effort levels if Grok exposes them on ACP or CLI.

### Phase 3 — Product polish

- Onboarding / recommendation engine entries (optional).
- Changelog + user-facing docs.
- Telemetry enums.
- MCP timeout policy note (document only if Grok supports a real config; do not invent Cursor-style speculative timeouts).
- Optional future: extract pure helpers to a package product if codec weight justifies it.

---

## 7. Connect flow (target UX)

Mirror Cursor/OpenCode, with clearer diagnostics than Codex auth collapse:

```
Connect
  → invalidate CLI env cache
  → resolve `grok` (login-shell PATH + supplemental hints)
  → preflight: version / `agent stdio` support advertisement
  → auth check: logged in to Grok (CLI-native)
  → optional: short ACP initialize + session/new smoke OR model list
  → on success: UserDefaults connected flag + start model polling
  → on failure: phase-specific message
       · executable missing / wrong binary
       · not authenticated → "Run `grok login`, then retry"
       · ACP unsupported / old CLI
       · MCP prep failure (if applicable)
```

**Sign out:** clear CE connected flag and local CE state; do **not** force-delete `~/.grok` credentials unless product explicitly offers “Sign out of Grok CLI” via `grok logout` (prefer separate, explicit action).

---

## 8. PATH and packaging lessons (from Codex incident)

| Risk | Mitigation |
| --- | --- |
| Multiple `grok` binaries / stale installs | Prefer version check; show resolved absolute path in Connect UI when connected |
| GUI app (`/Applications/RepoPrompt CE.app`) lacks interactive PATH | Use `ProcessEnvironmentBuilder` purpose `.acpAgent(providerID:)` + supplemental paths for `~/.local/bin` and `~/.grok/bin` in **login-relevant** profiles |
| Interactive terminal works, App fails | Document Connect using login-shell discovery; add fallback env hint in error text (existing `AgentCLILaunchDiagnostics` pattern) |
| Wrong tool advertised as auth failure | Classify errors; never map spawn/config errors to “Login with …” |

---

## 9. State, permissions, and migrations

| State | Owner | Notes |
| --- | --- | --- |
| Connected flag | UserDefaults | New key; default false |
| Model selection | Existing Agent Mode persistence | New kind branches in catalog |
| Tool permissions | `AgentPermissionSecureStore` + binding `grokBuild` | New document type; fail closed if missing |
| Preference snapshots | `AgentProviderPreferenceSnapshotStore` | Exhaustive switch updates |
| Secrets | Grok CLI store | CE may store optional API-related keys only if product needs them; Connect must not require `AIProviderType.grok` key |
| Classic migration | N/A for new kind | Ensure unknown future kinds still fail closed in permission decode |

---

## 10. Testing and validation matrix

| Layer | Command / action |
| --- | --- |
| Unit | Launch resolver, config, catalog raw values, binding decode |
| Integration (fake ACP) | Follow `ACPAgentSessionController*` / provider session identity tests patterns |
| Package | None for MVP (no new SwiftPM product) |
| Build | `make dev-swift-build PRODUCT=RepoPrompt` (and MCP product if shared enums affect it) |
| Live CE | Debug or release app: Connect → Agent Mode prompt → MCP tool → interrupt/cancel |
| MCP CLI | `rpce-cli-debug` agent_run with Grok Build model when wired |
| Style | `make dev-format` / `make dev-lint` on touched Swift |

Contribution gates: `rpce-contribution-check` preflight before commit/push.

---

## 11. Risks and open questions (resolved in Phase 0)

| # | Question | Why it blocks |
| --- | --- | --- |
| Q1 | Exact launch argv for stdio ACP (`grok agent stdio` vs flags order with `-m`) | Launch resolver freeze |
| Q2 | Does session config MCP list work, or must config.toml be patched (Cursor-style data dir)? | IntegrationConfiguration design |
| Q3 | Permission request shape vs Cursor/OpenCode | Binding UI + auto-approve mapping |
| Q4 | `session/load` confidence / resume IDs | Runner identity policy |
| Q5 | Model IDs stable for persistence | Catalog raw values |
| Q6 | Minimum Grok CLI version for ACP | Connect preflight message |
| Q7 | Headless: ACP vs `grok -p` | Phase 2 scope |
| Q8 | Extension methods `x.ai/*` needed for MVP? | Default **no** |
| Q9 | MCP tool timeout configurability | Docs only unless supported |
| Q10 | Display name / recommendation priority vs Claude/Codex | Product policy, post-MVP OK |

---

## 12. Maintainer-guidance check

| Item | Assessment |
| --- | --- |
| **User impact and invariant** | Cursor-like CLI Provider + Agent Mode via ACP; Grok Build isolated from xAI API chat provider. |
| **Root-cause confidence** | **Confirmed** that ACP is the correct seam (docs + Grok CLI agent-mode). Implementation details **unknown** until Phase 0 probes. |
| **Authority** | Grok CLI ACP + RPCE `ACPAgentProvider` stack; not Claude package; not Codex app-server. |
| **State-safety risks** | New kind/binding raw values; permission documents; connected flags; do not alias to `AIProviderType.grok`. |
| **Scale and observability risks** | Tool cards and Connect diagnostics required; model polling must not thrash; avoid whole-root scans. |
| **Recommended scope** | **Investigate first (Phase 0)** → implement Phase 1 MVP → Phase 2 headless. Do not start with package extraction. |
| **Validation boundary** | Phase 0: local `grok agent stdio` evidence. Phase 1: unit + live Connect + one Agent Mode turn on CE app. |

---

## 13. Deliverables checklist (this planning set)

| Artifact | Path | Purpose |
| --- | --- | --- |
| Overall plan | `.docs/Grok_Build/Planning.md` | This document |
| Phase 0 probe + wiring inventory | `.docs/Grok_Build/Phase0.md` | Pre-code investigation and file list |
| Phase 0 evidence | `.docs/Grok_Build/Phase0-evidence.md` | Probe results + frozen decisions (2026-07-20) |
| Future: implementation PRs | GitHub | Split Connect/launch vs Agent Mode if needed |

---

## 14. Implementation order (when coding starts)

1. Exhaustive enum scaffolding (`AgentProviderKind`, `ACPProviderID`, binding ID) so the project compiles with stubs.
2. `GrokBuildACPLaunchResolver` + Connect in settings.
3. `GrokBuildACPAgentProvider` + factory + runner path.
4. Permissions + catalog minimum.
5. Model polling + UI polish.
6. Headless (Phase 2).
7. Tests and live validation continuously, not only at the end.

### 14.1 Commit policy (mandatory)

After **each implementation step above** (and Phase 0 docs/evidence updates) **passes its local gate**, create a **git commit** before starting the next step:

1. Stage only that step’s intended files.
2. Run `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit` (rerun after any restage).
3. Commit with a focused message (what + why).
4. Do not batch unrelated steps into one commit unless they are inseparable for a green build.

Phase 0 gate for this policy: probe evidence written + frozen decisions recorded → one docs commit (this set).

---

## 15. References

- `docs/architecture/provider-plugins.md` — “How a new provider plugs in”, ACP carve-out.
- `Sources/RepoPrompt/Infrastructure/AI/Providers/Cursor/` — primary mirror.
- `Sources/RepoPrompt/Infrastructure/AI/Providers/OpenCode/` — secondary ACP mirror.
- `Sources/RepoPrompt/Features/AgentMode/Providers/ACP/ACPAgentProvider.swift`
- `Sources/RepoPrompt/Infrastructure/AI/ACP/ACPAgentProviderFactory.swift`
- `Sources/RepoPrompt/Features/AgentMode/Runtime/Runners/ACPIntegratedAgentModeRunner.swift`
- Grok user guide (local install): `~/.grok/docs/user-guide/15-agent-mode.md`, `14-headless-mode.md`, `02-authentication.md`, `07-mcp-servers.md`
- Existing HTTP Grok (do not confuse): `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokProvider.swift`
