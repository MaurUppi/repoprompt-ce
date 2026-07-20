# Phase 0 Evidence — Grok Build ACP Probe

**Date:** 2026-07-20
**Operator:** local probe scripts (no RPCE code changes)
**Parent:** [Planning.md](./Planning.md), [Phase0.md](./Phase0.md)
**Grok CLI:** `0.2.106` (`bde89716f679`)
**Resolved binary:** `~/.local/bin/grok` → `~/.grok/downloads/grok-0.2.106-macos-aarch64`
**Workspace cwd used:** `/Volumes/PM1733-7.68T/DevProjects/github_app/repoprompt-ce`

PII (email, tokens) redacted from this document. Raw JSON-RPC transcripts were not retained.

---

## A.0 Environment

| Field | Result |
| --- | --- |
| Interactive `which -a grok` | `~/.local/bin/grok`, `~/.grok/bin/grok` (same realpath) |
| Login shell `/bin/zsh -lc 'which -a grok; grok --version'` | Same first hit: `~/.local/bin/grok`, version **0.2.106** |
| Auth (CLI) | `grok models` prints **You are logged in with grok.com.** |
| `grok login status` | **Unsupported** (`unexpected argument 'status'`) — do not use for Connect |
| Auth store | `~/.grok/auth.json` present; OIDC-style entries under auth.x.ai |
| `~/.grok/config.toml` note | `permission_mode = "always-approve"` (affects permission probes) |

**A.0: PASS** — login-shell resolution works for this machine (unlike the prior dual-Codex PATH trap). Still ship supplemental PATH hints for other installs.

---

## Launch (L*)

| ID | Result | Notes |
| --- | --- | --- |
| L1 | **PASS** | `grok agent` has `stdio`; help documents options on **parent** `grok agent` |
| L2 | **PASS** | `grok agent stdio` stays up and speaks JSON-RPC |
| L3 | **PASS / FAIL pair** | **Works:** `grok agent -m grok-4.5 stdio`. **Fails:** `grok agent stdio -m grok-4.5` → `unexpected argument '-m'`, exit 2 |
| L4 | Not fully isolated | `--always-approve` exists on `grok agent`; this host already always-approves via config |
| L5 | **PASS** | `session/new` with project cwd accepted |
| L6 | Not stress-tested | Recommend CE login-shell + `~/.local/bin` + `~/.grok/bin` hints |
| L7 | **PASS** | Symlinks resolve to versioned download binary |

**Frozen launch:**

```text
command: grok
arguments: agent stdio
optional model: agent -m <modelId> stdio   # model flag BEFORE subcommand
```

Preflight help: `grok agent stdio --help` (and/or `grok agent --help` containing `stdio`).

---

## Version / support (V*)

| ID | Result |
| --- | --- |
| V1 | **PASS** — `grok 0.2.106 (…)` |
| V2 | **PASS** — agent stdio is first-class; ACP methods work with `protocolVersion: 1` |
| V3 | **Proposed min** — `0.2.106` known-good; set product floor at “version that implements agent stdio + initialize protocolVersion 1” (treat &lt; that as unsupported until better range known) |
| V4 | N/A — only one real binary family on this host |

---

## Authentication (A*)

| ID | Result | Notes |
| --- | --- | --- |
| A1 | **PASS** | `initialize` returns `authMethods`: `cached_token`, `grok.com`. `authenticate` with `methodId: "cached_token"` succeeds with account `_meta` (OIDC, subscription tier present) |
| A2 | **Not run destructively** | Did not `grok logout` (would break user session). Connect should treat missing/failed `cached_token` auth or missing `~/.grok/auth.json` as “run `grok login`” |
| A3 | **Partial** | Distinguishing paths designed: executable resolve vs auth method failure vs RPC error |
| A4 | **PASS (design)** | No dependency on CE `AIProviderType.grok` / Keychain xAI API key observed; CLI OIDC is authority |
| A5 | Documented only | `--reauth` exists; CE should **not** pass by default |

**CE wiring implication:** implement `preferredAuthMethodID` → prefer `cached_token` when listed (analogous to Cursor’s `cursor_login`), then let `ACPAgentSessionController` call `authenticate`.

**Connect auth check (recommended):**

1. Resolve executable.
2. Optional: `grok models` stdout contains `logged in` **or** short ACP initialize + `authenticate(cached_token)`.
3. Fail closed with explicit login guidance if authenticate fails.

---

## ACP lifecycle (P*)

CE-shaped initialize (from `ACPAgentSessionController`):

```json
{
  "protocolVersion": 1,
  "clientInfo": { "name": "RepoPrompt", "version": "…" },
  "clientCapabilities": {
    "fs": { "readTextFile": false, "writeTextFile": false },
    "terminal": false
  }
}
```

| ID | Result | Evidence summary |
| --- | --- | --- |
| P1 | **PASS** | Result includes `protocolVersion: 1`, `agentCapabilities.loadSession: true`, `mcpCapabilities.http/sse`, `authMethods`, `_meta` with `x.ai/*` capabilities |
| P2 | **PASS** | `notifications/initialized` accepted (no hard failure) |
| P3 | **PASS** | `session/new` `{ cwd, mcpServers: [] }` → `sessionId` + nested `models` catalog |
| P4 | **PASS** | `session/prompt` with text block → `stopReason: end_turn`; assistant output via `agent_message_chunk` (“PONG”) |
| P5 | **PASS** | Observed `session/update` types: `available_commands_update`, `user_message_chunk`, `agent_thought_chunk`, `agent_message_chunk`, `tool_call`, `tool_call_update`. Nesting matches CE: `params.update.sessionUpdate` |
| P6–P8 | **DEFERRED (host config)** | This host `permission_mode = "always-approve"`; write tool completed **without** `session/request_permission`. Re-probe on a machine with default permissions before claiming parity. Phase 1 still implements CE approval path like Cursor. |
| P9 | Not run | Interrupt/cancel deferred |
| P10 | **PASS** | `session/load` with prior `sessionId` + cwd + mcpServers succeeds; returns models. `loadSession: true` |
| P11 | Not separately scripted | Follow-up turns supported by loadSession design; single-session multi-prompt not double-checked |
| P12–P13 | Partial | Unknown method noise on stderr (`Method not found` for empty decode) — process continued |
| P14 | **PASS for MVP** | Many `_x.ai/*` notifications; **not required** for basic chat. Ignore extensions in Phase 1 |

**Important wire details for implementers:**

- Notifications use methods like `_x.ai/mcp/server_status`, `_x.ai/session/prompt_complete` — CE should ignore unknown methods safely (already typical for ACP clients).
- Stderr may show unrelated user MCP failures (e.g. missing `pencil` binary); Connect must not treat those as Grok auth failure.
- Session identity: UUID `sessionId` suitable for CE `ACPProviderSessionIdentity` with `loadSessionIDConfidence: .verified` when loadSession true.

---

## Models (M*)

| ID | Result |
| --- | --- |
| M1 | **PASS** — CLI: default **`grok-4.5`** only listed model |
| M2 | **PASS** — `session/new` / `session/load` embed `models.currentModelId` + `availableModels[]` with `modelId`, `name`, `description`, `_meta.totalContextTokens` (500000), `_meta.supportsReasoningEffort`, `_meta.reasoningEfforts` (`high` default, `medium`, `low`) |
| M3 | **PASS** — launch with `-m grok-4.5` before `stdio` works |
| M4 | **Stable raw:** `grok-4.5` |
| M5 | Effort levels present in session model `_meta`; product can map later (Phase 1 minimum: model id only) |
| M6 | Not run |

Usage `_meta` also references wire model name `grok-4.5-build` in usage blocks — catalog should persist **`grok-4.5`** as user-facing raw unless product decides otherwise.

---

## MCP (C*)

| ID | Result | Notes |
| --- | --- | --- |
| C1 | **PASS (shape)** | CE `RepoPromptMCPServerConfiguration.acpJSONObject` shape accepted: `{ type: "stdio", name, command, args, env: [{name,value}] }`. Wrong shape without `type` → `-32602 Invalid params` / `McpServer` enum |
| C1b | **Handshake** | Dummy `/usr/bin/true` as MCP → `status: unavailable`, `reason: handshake_failed` (expected). Server name **RepoPromptCE** appeared in `_x.ai/mcp/server_status`; init progress total increased (global MCPs + session server) |
| C2 | Not required for MVP path | Global `~/.grok` MCP config already loads (context-mode, playwright, pencil). Prefer **session mcpServers** inject like OpenCode/Cursor over rewriting user config |
| C3 | N/A for chosen path | Session inject is non-destructive |
| C4 | **DEFERRED** | Real RepoPrompt MCP binary handshake + tool call needs running CE MCP / stable CLI path — Phase 1 live validation |
| C5 | Deferred with permissions | |
| C6 | Unknown | No timeout config probed; do not invent |
| C7 | N/A | No project config rewrite used |

**Frozen MCP strategy:** **session/new + session/load `mcpServers`** using existing CE `acpJSONObject`. No Cursor-style project approval dir unless live validation proves Grok ignores session servers for real MCP binaries (unlikely given status events).

---

## Headless (H*)

| ID | Result |
| --- | --- |
| H1 | **PASS** — `grok -p "Reply with exactly PONG…" --output-format plain` → `PONG` |
| H2–H4 | Not fully matrixed | Phase 2 can use `-p` / streaming-json; interactive Agent Mode uses ACP |

---

## Failure matrix (Connect message themes)

| Class | Evidence | Message theme |
| --- | --- | --- |
| Not installed | PATH miss | Install Grok Build CLI; ensure login-shell PATH / `~/.local/bin` |
| Bad flag order | `stdio -m` exits 2 | Internal: never put model flags after `stdio` |
| Not authenticated | (designed) failed `cached_token` | Run `grok login`, then Connect |
| MCP dummy fail | handshake_failed on true | Do not fail Connect solely on optional MCP prep; fail Agent Mode MCP readiness separately if needed |
| User global MCP broken | pencil missing | Ignore unrelated MCP stderr for Connect success |
| Auth vs binary | Separate resolve vs authenticate | Distinct errors |

---

## Phase 0 exit criteria

| Gate | Status |
| --- | --- |
| L2 + P1–P5 on login-shell `grok` | **Met** |
| A1/A2 distinguish auth vs missing binary | **A1 met**; A2 not destructively proven — residual risk accepted with design |
| Launch argv frozen | **Met** (`agent stdio`; model via `agent -m <id> stdio`) |
| MCP inject path chosen | **Met** — CE session `mcpServers` / `acpJSONObject` |
| Permission path understood | **Partial** — host always-approve; implement CE path, re-probe later |
| Model raw ids listed | **Met** — `grok-4.5` (+ effort high/medium/low in meta) |
| Evidence written | **This file** |

**Verdict: Phase 0 is sufficient to start Phase 1 MVP coding**, with open follow-ups: real RepoPrompt MCP tool call, permission prompt without always-approve, cancel/interrupt.

---

## Frozen decisions (authoritative for Phase 1)

| Decision | Value |
| --- | --- |
| `AgentProviderKind` raw | `grokBuild` |
| `ACPProviderID` | `grokBuild` |
| `AgentProviderBindingID` | `grokBuild` |
| UI label | Grok Build |
| Launch command | `grok` |
| Launch arguments | `["agent", "stdio"]` |
| Model on launch | `["agent", "-m", modelId, "stdio"]` when model set |
| Min CLI version (known-good) | `0.2.106` (soft floor; reject if no stdio/agent) |
| Auth check | Prefer ACP `authenticate` / `cached_token`; secondary `grok models` “logged in” text; guide `grok login` |
| `preferredAuthMethodID` | `cached_token` if advertised |
| MCP inject strategy | Session `mcpServers` via CE `acpJSONObject` (`type: stdio`, …) |
| MCP client name / server name | `RepoPromptCE` (existing CE default) |
| Headless (Phase 2) | `grok -p` + output formats; ACP remains interactive authority |
| Default model raw | `grok-4.5` |
| Effort (Phase 1) | Optional; catalog can ignore until UI needed |
| Extensions `x.ai/*` | Ignore for MVP |
| Package product | None for MVP |
| HTTP `GrokProvider` / `AIProviderType.grok` | Untouched |

---

## Risks carried into Phase 1

1. **Permission UX unproven** under non-always-approve configs.
2. **Real RepoPrompt MCP handshake** not yet proven end-to-end (only shape + spawn attempt).
3. **User global MCP noise** (broken servers) must not break Connect.
4. **Session update volume** (thought chunks) — ensure CE streaming performance OK (same as other ACP agents).
5. **Hooks failures** in user environment (broken Claude hook path) — ignore for product readiness.

---

## Recommended Phase 1 first PR slice

1. Enum scaffolding: `AgentProviderKind.grokBuild`, `ACPProviderID.grokBuild`, binding id.
2. `GrokBuildACPLaunchResolver` + Connect card (PATH + version + auth).
3. `GrokBuildACPAgentProvider` + factory + `preferredAuthMethodID = cached_token`.
4. Catalog default `grok-4.5` from session models when available.
5. Live validation: Connect → Agent Mode prompt → (with CE MCP running) tool call.

Do **not** block coding on permission re-probe or full headless matrix.
