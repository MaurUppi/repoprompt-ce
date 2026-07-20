# Phase 3 — Product polish

**Status:** Planned
**Parent:** [Planning.md](./Planning.md)
**Depends on:** Phase 1 (required), Phase 2 (preferred)

---

## Goal

Ship polish that is not required for MVP correctness.

---

## Scope

- Onboarding / recommendation engine entries (optional product policy).
- Changelog + user-facing docs (install `grok`, `grok login`, Connect).
- Telemetry enums (do not overload HTTP `.grok` if already used).
- MCP timeout documentation **only if** Grok documents a real config (no speculative Cursor-style timeouts).
- Optional: extract pure helpers to `Packages/RepoPromptAgentProviders` if codec weight justifies it.
- Permission UX re-validation on non-always-approve hosts.

## Exit criteria

- [ ] User docs + changelog for the release that ships Grok Build.
- [ ] Telemetry/onboarding as product decides.
- [ ] Follow-ups filed for anything deferred.
