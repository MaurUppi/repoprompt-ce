# Phase 3 — Product polish + Oracle / Model Presets

**Status:** Complete for Oracle/Presets + live smoke — optional polish remains
**Parent:** [Planning.md](./Planning.md)
**Depends on:** Phase 1 (required), Phase 2 (preferred)

---

## Goal

Ship polish that is not required for MVP correctness, plus product surfaces deferred from Phase 2.

---

## Scope

### A/B — Oracle Model + Model Presets (implemented)

**Product decision:** Grok Build **is** available as an Oracle / Model Presets backend when Connect succeeds (same pattern as Cursor CLI / OpenCode).

| Item | Implementation |
| --- | --- |
| `AIProviderType.grokBuild` | Distinct from HTTP `.grok` (xAI API keys) |
| `AIModel.grokBuildCustom(name:)` | Persistence prefix `grokbuild_custom_<raw>` |
| `GrokBuildCLIProvider` | Headless ACP, **no** RepoPrompt MCP inject; text-only prompt suffix |
| Catalog | Effort options High/Medium/Low via `AgentModelCatalog` when connected |
| Settings | `updateAvailableModels` includes Grok Build when `isGrokBuildConnected` |

Oracle analysis / ask_oracle / plan-review / Model Presets pickers use `promptViewModel.availableModels` → now lists **Grok Build** when connected.

### Polish (remaining / optional)

- Onboarding / recommendation engine entries (optional product policy).
- Changelog + user-facing docs (install `grok`, `grok login`, Connect).
- Telemetry enums (do not overload HTTP `.grok` if already used).
- MCP timeout documentation **only if** Grok documents a real config.
- Optional: extract pure helpers to `Packages/RepoPromptAgentProviders`.
- Permission UX re-validation on non-always-approve hosts.

## Exit criteria

- [x] Oracle + Model Presets list Grok Build when connected (code path)
- [x] Stable raw ids `grokbuild_custom_grok-4.5:high|medium|low`
- [x] Distinct from HTTP Grok (xAI)
- [x] Focused tests + product build
- [x] Live Oracle smoke (`CE_GROK_ORACLE_SMOKE_OK`) — [Phase3-oracle-smoke.md](./Phase3-oracle-smoke.md)
- [x] Maintainer usage notes — [Usage.md](./Usage.md)
- [ ] Product release changelog (when shipping a named release)
- [ ] Recommendation onboarding entries (optional) — see [Gap-vs-Codex-Claude.md](./Gap-vs-Codex-Claude.md) G-01…G-13

## Key files

- `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/GrokBuildCLIProvider.swift`
- `Sources/RepoPrompt/Infrastructure/AI/Providers/AIProviderFactory.swift`
- `Sources/RepoPrompt/Infrastructure/AI/AIModel.swift`
- `Sources/RepoPrompt/Infrastructure/AI/ModelCatalog/Providers/ACPAIModelCatalog.swift`
- `Sources/RepoPrompt/Features/Settings/ViewModels/APISettingsViewModel.swift`
- `Tests/RepoPromptTests/AI/GrokBuildOracleModelCatalogTests.swift`
