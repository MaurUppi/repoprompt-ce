# Grok Build Support — Overall Plan (Outline)

**Status:** Active outline (implementation detail lives in phase files)
**Date:** 2026-07-20
**Goal:** Add **Grok Build** as a first-class Agent Mode / CLI Provider in RepoPrompt CE, at parity with **Cursor CLI** (ACP), not as Claude-compatible backend and not as the existing xAI HTTP `GrokProvider`.

**Authority:** `docs/architecture/provider-plugins.md`; Cursor/OpenCode under `Sources/RepoPrompt/Infrastructure/AI/Providers/{Cursor,OpenCode}/`.

---

## Decision

| Item | Choice |
| --- | --- |
| Runtime shape | **ACP** (`grok agent stdio`) |
| Template | Cursor ACP provider family |
| Kind / IDs | `grokBuild` (`AgentProviderKind`, `ACPProviderID`, `AgentProviderBindingID`) |
| CLI command | `grok` |
| Not | Claude package plugin; Codex app-server; reuse `AIProviderType.grok` HTTP |

---

## Phase index (one file each)

| Phase | File | Status |
| --- | --- | --- |
| 0 — ACP probe + wiring inventory | [Phase0.md](./Phase0.md) | **Complete** (gate open for Phase 1) |
| 0 — Probe evidence | [Phase0-evidence.md](./Phase0-evidence.md) | Complete |
| 1 — MVP (Connect + ACP Agent Mode + MCP + catalog min) | [Phase1.md](./Phase1.md) | **Complete** (live: list_agents + agent_run stream OK; MCP inject residual) |
| 2 — Headless + discovery + effort + MCP identity | [Phase2.md](./Phase2.md) | **Complete** (Oracle/Presets → Phase 3) |
| 3 — Product polish + Oracle/Presets | [Phase3.md](./Phase3.md) | Planned (includes A/B from Phase 2) |

---

## Invariants (all phases)

1. One ACP control plane shared with OpenCode/Cursor (`ACPAgentSessionController`).
2. Grok Build credentials = Grok CLI (`~/.grok` / `grok login`), not Codex/Claude/xAI API Keychain.
3. Stable raw values once shipped (`grokBuild`, model ids).
4. Connect errors classified (PATH / version / auth / ACP / MCP) — no false “re-login” collapse (Codex lesson).
5. Login-shell + supplemental PATH for GUI `/Applications` app (`~/.local/bin`, `~/.grok/bin`).

---

## Commit policy

After **each phase (or Phase 1 implementation step)** passes its gate:

1. Stage only intended files.
2. `.agents/skills/rpce-contribution-check/scripts/preflight.sh commit`
3. Focused git commit.
4. Do not batch unrelated steps.

---

## Toolchain note (local)

| Check | 2026-07-20 after Xcode 26.6 |
| --- | --- |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| `xcodebuild -version` | **Xcode 26.6** (17F113) |
| `swift package dump-package` | **OK** |
| `make doctor` | Swift/SDK OK; style tools optional; debug CLI may need install |

Authoritative build path remains SwiftPM + conductor (not required to open Xcode IDE). See `docs/architecture/xcode-workspace.md` only for optional generated workspace.

---

## References

- Phase detail files above
- `docs/architecture/provider-plugins.md`
- Cursor: `Sources/RepoPrompt/Infrastructure/AI/Providers/Cursor/`
- Grok CLI guides: `~/.grok/docs/user-guide/15-agent-mode.md`, `14-headless-mode.md`
- HTTP Grok (do not confuse): `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokProvider.swift`
