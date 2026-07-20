# Phase 1 — MVP (Cursor-parity core path)

**Status:** In progress / MVP implementation landed (build green; live Connect still recommended)
**Parent:** [Planning.md](./Planning.md)
**Depends on:** [Phase0.md](./Phase0.md) frozen decisions + [Phase0-evidence.md](./Phase0-evidence.md)

---

## Goal

Ship the smallest complete user path:

**CLI Providers → Connect Grok Build → Agent Mode multi-turn ACP → RepoPrompt MCP tools → model pick.**

---

## Scope

1. **Launch + Connect**
   - Login-shell-aware PATH + supplemental hints (`~/.local/bin`, `~/.grok/bin`).
   - Preflight: executable + `agent stdio` + **auth** (`cached_token` / `grok models` “logged in”).
   - CLI Providers card: Connect / Sign out / errors / optional model summary + resolved path.
2. **ACP interactive Agent Mode**
   - `ACPProviderID.grokBuild` + `GrokBuildACPAgentProvider`.
   - Factory + runner (shared `ACPIntegratedAgentModeRunner`).
   - `preferredAuthMethodID` → `cached_token` when advertised.
   - Session new/load, streaming, tool cards, permission UI via binding stack.
3. **RepoPrompt MCP injection**
   - Session `mcpServers` using CE `RepoPromptMCPServerConfiguration.acpJSONObject`.
4. **Model catalog minimum**
   - Default raw `grok-4.5`; discovery from session `models` / polling when available.
5. **Permissions binding**
   - `AgentProviderBindingID.grokBuild` + secure store + settings controls.
6. **Tests**
   - Launch resolver unit tests; exhaustiveness via compile; focused ACP fakes as needed.
7. **Validation**
   - `make dev-swift-build PRODUCT=RepoPrompt`
   - Focused tests
   - Live Connect + one Agent Mode turn (+ MCP if CE MCP installed)

## Non-goals

- Recommendations wizard polish
- Full headless parity (→ Phase 2)
- `x.ai/*` ACP extensions
- Claude plugin package
- Changing HTTP `GrokProvider`

---

## Frozen inputs from Phase 0

| Item | Value |
| --- | --- |
| Launch | `grok` + `["agent","stdio"]`; model: `["agent","-m",id,"stdio"]` |
| Auth | `authenticate` / `cached_token`; user `grok login` |
| MCP | Session `mcpServers` CE shape |
| Default model | `grok-4.5` |
| Source dir | `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/` |

Wiring inventory: **Part B of Phase0.md**.

---

## Implementation steps (each step → validate → commit)

1. Enum scaffolding (`AgentProviderKind`, `ACPProviderID`, binding ID) — compile green.
2. `GrokBuildACPLaunchResolver` + Connect UI/APISettings.
3. `GrokBuildACPAgentProvider` + factory + runner path.
4. Permissions + catalog minimum.
5. Model polling + polish.
6. Tests + live validation.

---

## Exit criteria

- [ ] Connect works from CE app (login-shell PATH). *(code landed; live verify pending)*
- [ ] Agent Mode turn streams assistant text.
- [ ] RepoPrompt MCP tool callable when MCP server available.
- [x] Focused tests + product build green (`swift build --product RepoPrompt` / `repoprompt-mcp`; `GrokBuildACPLaunchResolverTests` + catalog tests).
- [ ] Commits per step with contribution preflight.
