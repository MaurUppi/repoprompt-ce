# Phase 2 — Headless + discovery + deferred product surfaces

**Status:** Complete (core) — effort UI, polling, MCP client identity fix
**Parent:** [Planning.md](./Planning.md)
**Depends on:** [Phase1.md](./Phase1.md) **COMPLETE**

---

## Goal

Close Phase 1 residuals and reach **Cursor-like parity** beyond the Agent Mode MVP path:

1. Headless / discovery / polling lifecycle
2. Reasoning effort UI
3. Live RepoPromptCE MCP tool exposure inside Grok ACP sessions

Oracle / Model Presets moved to **[Phase3.md](./Phase3.md)**.

---

## Implementation status (2026-07-20)

| Area | Status |
| --- | --- |
| **C** Reasoning effort UI + ACP apply | **Done** |
| Headless + model polling wiring | **Done** |
| **D** Live RepoPromptCE MCP | **Fixed** — `MCPClientIdentity` grok family |
| **A/B** Oracle + Model Presets | **Moved → Phase 3** |
| **E** Non-ad-hoc UI smoke | Optional; no Apple Development identity required for D |

---

## C — Reasoning effort (done)

- Compound raws `grok-4.5:high|medium|low`; menu **Grok 4.5 High/Medium/Low**
- ACP: `session/set_model` + `session/set_mode`
- Launch `-m` strips effort

---

## Headless + polling (done)

- Agent Mode + Context Builder subscribe to `GrokBuildACPModelPollingService`
- Headless applies model + effort before prompt

---

## D — Live RepoPromptCE MCP (fixed)

### Root cause

Grok’s MCP client identity is **not** the bare string `grok`:

| Source | Example name |
| --- | --- |
| Parent process (bootstrap handshake) | `grok-0.2.106-macos-aarch64` |
| MCP `clientInfo.name` (live capture) | `grok-shell-RepoPromptCE` |

Agent Mode policy / expected-PID routing keys use **`grok`** (`AgentProviderKind.grokBuildMCPClientID`).

`MCPClientIdentity` did not map either form into the `grok` family → policy match failed → tools never listed.

### Fix

In `MCPClientIdentity.canonicalFamilyID`:

- `grok`, `grok-*` (versioned binary **and** `grok-shell-<ServerName>`) → family **`grok`**
- Headless agent client set includes `grok`

### Verify

After rebuild: Grok ACP session injects RepoPromptCE; agent can call a read-only CE tool (e.g. windows/tree).

Signing / Apple Developer Program is **not** required.

---

## A/B — moved to Phase 3

Oracle Model + Model Presets Grok selection is **out of Phase 2**. See [Phase3.md](./Phase3.md).

---

## Exit criteria

- [x] Headless path + polling wired
- [x] Reasoning effort options High/Medium/Low
- [x] Live RepoPromptCE MCP client identity fix (`grok-*` binary + `grok-shell-*`)
- [x] Oracle/Presets deferred to Phase 3
- [x] Focused tests + commits

---

## Key files

- `Sources/RepoPrompt/Infrastructure/MCP/MCPClientIdentity.swift`
- `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/GrokBuildModelSpecifier.swift`
- `Sources/RepoPrompt/Infrastructure/AI/ACP/ACPAgentSessionController.swift`
- `Tests/RepoPromptTests/MCP/MCPClientIdentityGrokFamilyTests.swift`
