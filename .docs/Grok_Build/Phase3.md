# Phase 3 — Product polish

**Status:** Planned
**Parent:** [Planning.md](./Planning.md)
**Depends on:** Phase 1 (required), Phase 2 (preferred)

---

## Goal

Ship polish that is not required for MVP correctness, plus product surfaces deferred from Phase 2.

---

## Scope

### From Phase 2 (deferred product decision)

#### A/B — Oracle Model + Model Presets

| Surface | Phase 1–2 stance |
| --- | --- |
| Oracle Model | No Grok Build (expected) |
| Model Presets (Oracle Model Presets) | No Grok (same `AIModel` path) |

**Phase 3 work (if product accepts Grok as oracle backend):**

- Add `AIProviderType` / `AIModel` cases for Grok Build (mirror Cursor/OpenCode CLI provider pattern).
- Implement `GrokBuildCLIProvider` (headless ACP, no tools / oracle-safe mode as product decides).
- Wire `updateAvailableModels` when Grok Build is connected so Oracle + Model Presets list Grok.
- Ensure presets round-trip stable raw ids (`grokBuild` + `grok-4.5` [+ effort]).
- MCP “Use Oracle Model Presets” must resolve Grok without collapsing to Claude/Codex.

**If product declines:** document permanently in user-facing docs that Grok Build is Agent Mode / Context Builder agent only.

### Polish

- Onboarding / recommendation engine entries (optional product policy).
- Changelog + user-facing docs (install `grok`, `grok login`, Connect).
- Telemetry enums (do not overload HTTP `.grok` if already used).
- MCP timeout documentation **only if** Grok documents a real config (no speculative Cursor-style timeouts).
- Optional: extract pure helpers to `Packages/RepoPromptAgentProviders` if codec weight justifies it.
- Permission UX re-validation on non-always-approve hosts.

## Exit criteria

- [ ] Oracle + Model Presets either list Grok when connected **or** permanent non-goal documented for users.
- [ ] User docs + changelog for the release that ships Grok Build.
- [ ] Telemetry/onboarding as product decides.
- [ ] Follow-ups filed for anything deferred.
