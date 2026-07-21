# Phase 3 — Product polish + Oracle / Model Presets

**Status:** **Complete** (core). Incomplete polish migrated to [Phase4.md](./Phase4.md).
**Parent:** [Planning.md](./Planning.md)
**Depends on:** Phase 1 (required), Phase 2 (preferred)

---

## Goal

Ship Oracle / Model Presets for Grok Build plus maintainer usage and live smoke evidence.

---

## Scope (completed)

### A/B — Oracle Model + Model Presets

**Product decision:** Grok Build **is** available as an Oracle / Model Presets backend when Connect succeeds (same pattern as Cursor CLI / OpenCode).

| Item | Implementation |
| --- | --- |
| `AIProviderType.grokBuild` | Distinct from HTTP `.grok` (xAI API keys) |
| `AIModel.grokBuildCustom(name:)` | Persistence prefix `grokbuild_custom_<raw>` |
| `GrokBuildCLIProvider` | Headless ACP, **no** RepoPrompt MCP inject; text-only prompt suffix |
| Catalog | Effort options High/Medium/Low via `AgentModelCatalog` when connected |
| Settings | `updateAvailableModels` includes Grok Build when `isGrokBuildConnected` |

Oracle analysis / ask_oracle / plan-review / Model Presets pickers use `promptViewModel.availableModels` → lists **Grok Build** when connected.

---

## Exit criteria

- [x] Oracle + Model Presets list Grok Build when connected (code path)
- [x] Stable raw ids `grokbuild_custom_grok-4.5:high|medium|low`
- [x] Distinct from HTTP Grok (xAI)
- [x] Focused tests + product build
- [x] Live Oracle smoke (`CE_GROK_ORACLE_SMOKE_OK`) — [Phase3-oracle-smoke.md](./Phase3-oracle-smoke.md)
- [x] Maintainer usage notes — [Usage.md](./Usage.md)
- [x] Incomplete polish **migrated to Phase 4** (recommendations, changelog, permission re-validation, package extract)

### Migrated to Phase 4 (was open here)

| Former Phase 3 item | Phase 4 |
| --- | --- |
| Recommendation / onboarding entries | T1 G-01…G-13 |
| Product release changelog | G-20 / ship note |
| Permission UX re-validation | T2-perm |
| Optional package extract | Shelved in Phase 4 non-goals |
| MCP timeout docs | G-15 / evidence-gated |

---

## Key files

- `Sources/RepoPrompt/Infrastructure/AI/Providers/GrokBuild/GrokBuildCLIProvider.swift`
- `Sources/RepoPrompt/Infrastructure/AI/Providers/AIProviderFactory.swift`
- `Sources/RepoPrompt/Infrastructure/AI/AIModel.swift`
- `Sources/RepoPrompt/Infrastructure/AI/ModelCatalog/Providers/ACPAIModelCatalog.swift`
- `Sources/RepoPrompt/Features/Settings/ViewModels/APISettingsViewModel.swift`
- `Tests/RepoPromptTests/AI/GrokBuildOracleModelCatalogTests.swift`
