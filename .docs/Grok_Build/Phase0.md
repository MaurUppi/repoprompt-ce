# Phase 0 — ACP Probe Checklist + AgentProviderKind Wiring Inventory

**Status:** **COMPLETE** — gate open for [Phase1.md](./Phase1.md)
**Date:** 2026-07-20 (closed after Xcode 26.6 toolchain verify + residual probes)
**Parent:** [Planning.md](./Planning.md)
**Evidence:** [Phase0-evidence.md](./Phase0-evidence.md)

Phase 0 is investigation only (**no product `AgentProviderKind` code**). Outcome: freeze launch/auth/MCP/model decisions and list every CE touch for Phase 1.

---

## Part A — ACP probe checklist (filled)

### A.0 Probe environment

| Field | Record |
| --- | --- |
| Date / operator | 2026-07-20 / local agent probes |
| Host OS | macOS 26.x arm64 |
| Interactive `which -a grok` | `~/.local/bin/grok`, `~/.grok/bin/grok` (same realpath) |
| Login shell | Same first hit; `grok 0.2.106` |
| Auth | `grok models` → **You are logged in with grok.com.** |
| RepoPrompt under test | `/Applications/RepoPrompt CE.app` present; probes used CLI ACP (no CE source changes) |
| Workspace cwd | repo root `repoprompt-ce` |
| Xcode (post-install) | **26.6** (`xcode-select` → Xcode.app); `swift package dump-package` OK; `make doctor` SDK OK |

**A.0 PASS**

### A.1 Launch surface

| ID | Result | Evidence |
| --- | --- | --- |
| L1 | **PASS** | `grok agent` / `stdio` help |
| L2 | **PASS** | process stays up on stdio |
| L3 | **PASS** | model flags **before** `stdio` only (`agent -m id stdio`) |
| L4 | **PASS** | `grok agent --always-approve stdio` stays alive |
| L5 | **PASS** | `session/new` with workspace cwd |
| L6 | **PASS** | absolute `~/.local/bin/grok` + `PATH=/usr/bin:/bin` still initializes ACP |
| L7 | **PASS** | symlink → `~/.grok/downloads/grok-0.2.106-macos-aarch64` |

**Frozen launch:** `grok` + `["agent","stdio"]`; with model `["agent","-m",modelId,"stdio"]`.

### A.2 Version / support

| ID | Result |
| --- | --- |
| V1–V2 | **PASS** — 0.2.106; `protocolVersion: 1` initialize |
| V3 | Known-good **0.2.106**; require working `agent stdio` |
| V4 | Single binary family on probe host |

### A.3 Authentication

| ID | Result |
| --- | --- |
| A1 | **PASS** — `authMethods`: `cached_token`, `grok.com`; `authenticate(cached_token)` OK when logged in |
| A2 | **PASS (simulated)** — empty `HOME`: `grok models` → **You are not authenticated.**; init lists `grok.com` without usable `cached_token` session |
| A3 | **PASS (design)** — executable vs auth vs RPC separated for Connect messages |
| A4 | **PASS** — no CE `AIProviderType.grok` Keychain required |
| A5 | `--reauth` exists; CE must not pass by default |

### A.4 ACP lifecycle

| ID | Result |
| --- | --- |
| P1–P5 | **PASS** — initialize, initialized, session/new, session/prompt, streaming updates |
| P6–P8 | **DEFERRED** — host `permission_mode=always-approve`; tools run without permission RPC. Phase 1 still implements CE approval path |
| P9 | Deferred (cancel/interrupt) |
| P10 | **PASS** — `session/load` + `loadSession: true` |
| P11 | Supported by loadSession design |
| P14 | **PASS for MVP** — ignore `_x.ai/*` extensions |

Wire note: `session/update` uses `params.update.sessionUpdate` (matches CE controller).

### A.5 Models

| ID | Result |
| --- | --- |
| M1–M4 | **PASS** — default raw **`grok-4.5`**; session embeds availableModels + effort meta high/medium/low |
| M5 | Effort in `_meta`; Phase 1 may ship model-only UI |
| M6 | Not run |

### A.6 MCP

| ID | Result |
| --- | --- |
| C1 | **PASS (shape)** — CE `acpJSONObject` (`type:stdio`, name, command, args, env[{name,value}]) accepted; dummy binary → handshake_failed (expected) |
| C2–C3 | Not required — prefer session inject over config rewrite |
| C4 | **DEFERRED** — real RepoPrompt MCP binary → Phase 1 live |
| C6 | Unknown; do not invent timeouts |

### A.7 Headless (Phase 2 input)

| ID | Result |
| --- | --- |
| H1 | **PASS** — `grok -p` plain → PONG |
| H2 | **PASS** — streaming-json NDJSON thought/text/end |
| H3–H4 | Optional; Phase 2 |

### A.8 Failure matrix (Connect themes)

| Class | CE message theme |
| --- | --- |
| Not installed | Install Grok Build; PATH / docs |
| Not executable | Permission / not executable |
| Wrong/old binary | Upgrade Grok Build CLI |
| Not authenticated | Run `grok login`, then Connect |
| ACP unsupported | CLI lacks agent stdio |
| MCP prep failed | MCP setup detail (do not fail Connect only on unrelated global MCP noise) |
| Initialize timeout | Timed out talking to Grok ACP |
| Transport crash | Session ended; retry |

### A.9 Exit criteria

- [x] L2 + P1–P5
- [x] Auth vs binary distinguishable (A1/A2)
- [x] Launch argv frozen
- [x] MCP session inject chosen (real tool call → Phase 1)
- [x] Permission path: implement CE handler; host always-approve noted
- [x] Model raw `grok-4.5`
- [x] Evidence file
- [x] Xcode 26.6 / `dump-package` verified for subsequent implementation

**Gate: OPEN for Phase 1.**

### A.10 Frozen decisions

| Decision | Value |
| --- | --- |
| `AgentProviderKind` / `ACPProviderID` / binding | `grokBuild` |
| UI label | Grok Build |
| Launch | `grok` `agent stdio`; model via `agent -m <id> stdio` |
| Min CLI | known-good 0.2.106; require stdio ACP |
| Auth | `cached_token` + `grok login` guidance |
| MCP | session `mcpServers` + CE `acpJSONObject` |
| Default model | `grok-4.5` |
| Headless | Phase 2 (`grok -p` / streaming-json) |
| Extensions | ignore `x.ai/*` for MVP |

---

## Part B — Wiring inventory (Phase 1 touch list)

Legend: **R** MVP · **S** strong parity · **L** later · **T** tests

### B.1 New sources

| Path | Priority |
| --- | --- |
| `…/GrokBuild/GrokBuildAgentConfig.swift` | R |
| `…/GrokBuildACPLaunchResolver.swift` | R |
| `…/GrokBuildACPAgentProvider.swift` | R |
| `…/GrokBuildAgentToolPreferences.swift` | R |
| `…/GrokBuildCLIProvider.swift` | S |
| `…/GrokBuildACPModelPollingService.swift` | S |
| `…/GrokBuildIntegrationConfiguration.swift` | L (session MCP OK; only if live needs Cursor-style prep) |
| `…/GrokBuildACPHeadlessAgentProvider.swift` | L (Phase 2) |
| `…/GrokBuildACPEventNormalizer.swift` | L if needed |
| `Tests/…/GrokBuildACPLaunchResolverTests.swift` | T |

Do **not** touch Claude package, Codex app-server, or HTTP `GrokProvider.swift`.

### B.2 Enums / bindings

`AgentRuntimeProviderService`, `ACPAgentProvider` (`ACPProviderID`), `ACPAgentProviderFactory`, `AgentProviderBindingID` + binding models/secure store/preference/snapshot/service, `CLILaunchProfile` / `CLIPathHints`, Sentry labels (S).

### B.3 ACP / Agent Mode

Factory + `ACPIntegratedAgentModeRunner` neutrality, `AgentModeViewModel`, MCP policies/session store, optional headless bridges (L).

### B.4 Catalog

`AgentModel` / `AgentModelCatalog` / optional `ACPAIModelCatalog`.

### B.5 Settings UI

`CLIProvidersSettingsView` card, `APISettingsViewModel` connect state, permission controls, `grokBuildConnectionChanged`, WindowStateManager polling shutdown (S).

### B.6 Onboarding / recommendations

Phase 3 / L unless needed for compile exhaustiveness.

### B.7 Tests

Mirror Cursor/OpenCode resolver + identity + connected-key lists; compiler exhaustiveness.

### B.8 Docs

Phase files here; user README at ship (Phase 3).

### B.9 Cursor → GrokBuild map

See evidence / Planning naming table; primary mirror is Cursor under `Providers/Cursor/`.

### B.10 Non-touch

Claude package · Codex managed auth · HTTP Grok · dynamic plugins.

---

## Part C — Execution record

1. ~~Fill A.0~~ done
2. ~~L/V/P/A/C probes~~ done
3. ~~Frozen A.10~~ done
4. ~~Evidence~~ `Phase0-evidence.md`
5. ~~Xcode 26.6 verify~~ `dump-package` + `make doctor`
6. Residual: L4/L6/A2-sim/H2 done 2026-07-20
7. **Next:** [Phase1.md](./Phase1.md) implementation (code)

---

## Part D — Maintainer-guidance check

| Item | Assessment |
| --- | --- |
| User impact | Cursor-like Grok Build via ACP is feasible |
| Confidence | Seam **confirmed**; MVP wire details frozen |
| Authority | Grok CLI ACP + CE ACP stack |
| State-safety | Raw values frozen before code |
| Scope | Phase 0 complete → Phase 1 only |
| Validation | Login-shell grok + ACP P1–P5 + MCP shape; live MCP/tool + non-always-approve permission → Phase 1 |
