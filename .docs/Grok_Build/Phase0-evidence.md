# Phase 0 Evidence — Grok Build ACP Probe

**Date:** 2026-07-20
**Operator:** local probe scripts (no RPCE product code)
**Parent:** [Planning.md](./Planning.md), [Phase0.md](./Phase0.md)
**Grok CLI:** `0.2.106` (`bde89716f679`)
**Resolved binary:** `~/.local/bin/grok` → `~/.grok/downloads/grok-0.2.106-macos-aarch64`
**Workspace cwd:** `/Volumes/PM1733-7.68T/DevProjects/github_app/repoprompt-ce`

PII redacted. Raw JSON-RPC transcripts not retained.

---

## Toolchain (Xcode 26.6)

| Check | Result |
| --- | --- |
| Xcode.app version | **26.6** (build 17F113) |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3), target macosx26.0 |
| macOS SDK | MacOSX26.5.sdk (via Xcode) |
| `swift package dump-package` | **OK** (RepoPromptCE, 11 targets) |
| `make doctor` | Required tools + SDK + SwiftUI glass probe **OK**; SwiftFormat/SwiftLint missing optional; debug CLI not installed; no Apple Development identity (use `ALLOW_ADHOC_SIGNING=1` or set `SIGN_IDENTITY`) |

Earlier CLT-only failure (`swiftLanguageModes` / PackageDescription) is resolved by selecting full Xcode.

---

## A.0 Environment

| Field | Result |
| --- | --- |
| Interactive / login-shell `grok` | Same preferred binary 0.2.106 |
| Auth | Logged in with grok.com |
| `grok login status` | Unsupported — do not use |
| Host permission config | `~/.grok/config.toml`: `permission_mode = "always-approve"` |

**A.0 PASS**

---

## Launch (L*)

| ID | Result | Notes |
| --- | --- | --- |
| L1 | PASS | agent stdio documented |
| L2 | PASS | stdio JSON-RPC |
| L3 | PASS | `agent -m id stdio` only; post-stdio `-m` exits 2 |
| L4 | PASS | `--always-approve stdio` stays alive |
| L5 | PASS | cwd = workspace |
| L6 | PASS | absolute grok + thin PATH initializes |
| L7 | PASS | stable download realpath |

```text
command: grok
arguments: agent stdio
optional: agent -m <modelId> stdio
```

---

## Version (V*)

PASS — 0.2.106; protocolVersion 1; known-good floor.

---

## Authentication (A*)

| ID | Result |
| --- | --- |
| A1 | PASS — `cached_token` + `grok.com`; authenticate OK when logged in |
| A2 | PASS (empty HOME) — models: **You are not authenticated.**; init without session token path usable as Connect fail |
| A4 | PASS — CLI OIDC authority, not CE HTTP Grok key |

Connect auth recipe:

1. Resolve executable.
2. Prefer short ACP initialize + `authenticate(cached_token)` **or** `grok models` contains logged in.
3. Else: run `grok login`, retry.

`preferredAuthMethodID` → `cached_token` when listed (Cursor analogue: `cursor_login`).

---

## ACP lifecycle (P*)

| ID | Result |
| --- | --- |
| P1–P5 | PASS — full chat path; assistant “PONG” |
| P6–P8 | Deferred — always-approve host |
| P10 | PASS — session/load |
| P14 | MVP ignores `_x.ai/*` |

Update nesting matches CE: `params.update.sessionUpdate`
(`agent_thought_chunk`, `agent_message_chunk`, `tool_call`, …).

---

## Models (M*)

Default raw **`grok-4.5`**. Session model list + reasoning efforts high/medium/low in `_meta`. Usage may mention `grok-4.5-build` — persist **`grok-4.5`** for users.

---

## MCP (C*)

CE shape accepted:

```json
{
  "type": "stdio",
  "name": "RepoPromptCE",
  "command": "…",
  "args": [],
  "env": [{ "name": "…", "value": "…" }]
}
```

Missing `type` → `-32602` Invalid params.
Dummy command → `handshake_failed` (shape OK).
Real RepoPrompt MCP tool call → Phase 1 live.
Global user MCP noise (e.g. missing pencil) must not fail Connect.

---

## Headless (H*)

| ID | Result |
| --- | --- |
| H1 | PASS plain PONG |
| H2 | PASS streaming-json NDJSON (`thought` / `text` / `end`) |

---

## Frozen decisions

| Decision | Value |
| --- | --- |
| Kind / ACP / binding | `grokBuild` |
| Launch | as above |
| Auth | `cached_token` / `grok login` |
| MCP | session `mcpServers` CE acpJSONObject |
| Default model | `grok-4.5` |
| Package product | none for MVP |

---

## Phase 0 exit

**COMPLETE.** Phase 1 may start coding. Residual live items: real RepoPrompt MCP handshake, permission RPC without always-approve, interrupt/cancel.
