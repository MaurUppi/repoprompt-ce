# Phase 4 — T1 product first-class + T2 contract-faithful ACP

**Status:** Implementation landed (T1 G-01/02/10–14/17 + T2-perm notes); G-15/G-16 optional still open
**Parent:** [Planning.md](./Planning.md)
**Depends on:** Phase 3 core (Oracle/Presets + live smoke)
**Authority:** [Gap-vs-Codex-Claude.md](./Gap-vs-Codex-Claude.md), [Benefits-Risks-Codex-Depth-No-Fork.md](./Benefits-Risks-Codex-Depth-No-Fork.md)
**Constraint:** CE-only integration. Do **not** fork or patch [xai-org/grok-build](https://github.com/xai-org/grok-build). No xAI Python SDK.

---

## Goal

Raise Grok Build to **Codex-depth in CE product terms** (T1) and **contract-faithful ACP/config use** (T2), without claiming Codex protocol parity (T4) or shipping Grok-specific ACP extension clients (T3).

---

## Scope

### T1 — Product first-class (must ship)

| ID | Work |
| --- | --- |
| **G-01** | Stop forcing `grokBuildAvailable: false` in MCP agent defaults availability |
| **G-02** | Add `grokBuildCLI` to `ProviderStatusSnapshot` (+ filtered / hasAny\* / status grids) |
| **G-10** | Chat / Oracle recommendation when Grok Build is ready (`ChatBackendKind.grokBuild`) |
| **G-11** | Context Builder recommendation: after Cursor, prefer Grok when ready |
| **G-12** | MCP role `SelectionCandidate` chains include Grok Build fallbacks |
| **G-13** | Onboarding / recommendation wizard status UI shows Grok Build |
| **G-14** | Focused tests: status snapshot, recommendation ranking, effort/MCP identity (existing + new) |
| **G-17** | Startup `probeCachedGrokBuildConnection` in context-builder validation task |

### T2 — Contract-faithful (this phase, CE-only)

| ID | Work |
| --- | --- |
| **T2-perm** | Document permission mapping (CE Default/Full Access ↔ Grok `default` / `bypassPermissions` / `--always-approve`); keep Cursor-like two-level UI unless Grok exposes richer ACP modes to CE without fork |
| **T2-errors** | Keep Connect/error classification aligned with Grok login/PATH/ACP messages (already partial; extend tests) |
| **G-15** | Optional `GrokBuildIntegrationConfiguration` for `~/.grok/config.toml` MCP — **design only if not shipped**; prefer ACP inject for Agent Mode; no silent broad config writes |
| **G-16** | MCP tool grant set = Cursor subset — **evidence-gated**; do not widen without live missing-tool reports |

### Migrated from Phase 3 (incomplete polish)

| Item | Phase 3 origin | Phase 4 disposition |
| --- | --- | --- |
| Recommendation / onboarding entries | Exit criteria unchecked | **In scope T1** (G-01…G-13) |
| Product release changelog | Exit criteria unchecked | **In scope T1 polish** (G-20) when shipping; stub note in `Changelog.swift` when feature lands if release not cut |
| Telemetry enums | Optional polish | Done for `grok_build` agent kind; no further T4-style events |
| MCP timeout documentation | Optional | Defer to G-15 / Grok docs; no invented timeouts |
| Extract helpers to `Packages/RepoPromptAgentProviders` | Optional | **Shelved** (not required for T1/T2) |
| Permission UX re-validation on non-always-approve hosts | Optional | **T2-perm** manual note + default/full access only |

### Explicitly shelved (record only)

| Tier | Content | Why shelved |
| --- | --- | --- |
| **T3** | Client for Grok ACP extensions `x.ai/fs/*`, git, worktree, rewind, auth URL/code, terminal host methods | High churn; needs capability discovery + large CE surface; ROI after T1/T2 |
| **T4** | Codex app-server twin, steer-ack, goal/computer-use, Claude package pattern | Protocol non-goal; see Gap Class A |
| **xai-sdk** | Python gRPC cloud SDK | Wrong product surface; see [Research-xai-sdk-python.md](./Research-xai-sdk-python.md) |

T3/T4 backlog remains in [Benefits-Risks-Codex-Depth-No-Fork.md](./Benefits-Risks-Codex-Depth-No-Fork.md) §1–§5 and Gap Class A / optional T3.

---

## Product policy (recommendations)

Priority order (do **not** displace Codex as preferred default when ready):

| Surface | Order when multiple ready |
| --- | --- |
| Chat / Oracle | Codex → OpenAI API → Claude Code → **Grok Build** (Grok only becomes default when others absent) |
| Free-tier chat path | Claude → Codex → OpenAI → **Grok Build** last among CLIs if free path used |
| Context Builder | Codex → Claude → Cursor → **Grok Build** |
| MCP role candidates | Existing chains first; append Grok `grok-4.5` / `grok-4.5:medium` as late fallbacks |

Planning model raw for Grok Oracle: `grokbuild_custom_grok-4.5:medium` (stable prefix).

---

## Exit criteria

- [x] G-01, G-02: status + MCP agent availability use real Grok connected/verified state
- [x] G-10–G-13: recommendations + wizard grids include Grok; default only when sole CLI-class option
- [x] G-17: cached Grok probe on context-builder validation (pattern: Cursor ACP poll refresh)
- [x] G-14: focused unit tests green (`GrokBuildRecommendationStatusTests` + existing GrokBuild suite)
- [x] T2-perm: documented in this file + Usage.md short note (+ prefs detail strings)
- [x] Phase 3 leftovers disposition recorded (this file)
- [x] T3/T4 remain documented as shelved (no code for extension clients / protocol twin)
- [x] Focused `make dev-test FILTER=GrokBuild` / AutoRecommendationEngine / ContextBuilderModelStartupSelection
- [ ] G-15 IntegrationConfiguration (optional, evidence-gated)
- [ ] G-16 MCP grant widen (evidence-gated)
- [ ] G-20 product release changelog at named release

---

## Key files (implementation)

| Area | Path |
| --- | --- |
| Status DTO | `Features/AgentMode/Recommendations/RecommendationTypes.swift` |
| Engine | `Features/AgentMode/Recommendations/AutoRecommendationEngine.swift` |
| Connect / probe | `Features/Settings/ViewModels/APISettingsViewModel.swift` |
| Wizard UI | `Features/AgentMode/Views/RecommendationWizardPopoverView.swift` |
| Role candidates | `Features/AgentMode/Models/ModelSelection/AgentModelCatalog.swift` |
| Permissions icon | `Features/Settings/Views/PermissionsSettingsView.swift` |
| Tests | `Tests/RepoPromptTests/…` (Grok recommendation / status) |

---

## Permission mapping (T2-perm)

| CE control | Grok Build equivalent (public CLI/docs) |
| --- | --- |
| Default (managed) | ACP tool permission prompts; no `--always-approve` |
| Full Access | Auto-approve ACP tool permissions (aligns with Grok `--always-approve` / `bypassPermissions` intent) |
| Sandbox profiles / acceptEdits / hooks | **Not** exposed as separate CE pickers in Phase 4; users configure via `~/.grok` / Grok TUI |

---

## Non-goals

1. Forking or vendoring `grok-build` crates into CE.
2. Implementing T3 `x.ai/*` clients.
3. Codex/Claude native runtime ports.
4. Merging HTTP `AIProviderType.grok` with Grok Build.
5. Silent mutation of large portions of `~/.grok/config.toml` without user intent.

---

## Validation

```bash
make dev-test FILTER=GrokBuild
make dev-test FILTER=MCPClientIdentityGrokFamily
make dev-test FILTER=ContextBuilderModelStartupSelection
# after implementation: recommendation-focused filters as added
```

Live smoke (optional, credentials required): Oracle + agent_run per [Usage.md](./Usage.md).
