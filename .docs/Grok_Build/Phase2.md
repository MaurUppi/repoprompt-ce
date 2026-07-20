# Phase 2 — Headless + discovery parity

**Status:** Planned
**Parent:** [Planning.md](./Planning.md)
**Depends on:** Phase 1 MVP complete

---

## Goal

Match Cursor/OpenCode **headless / discovery** surfaces so Grok Build participates in Context Builder, Prompt availability, and non-interactive agent runs.

---

## Scope

- `GrokBuildACPHeadlessAgentProvider` and/or `grok -p` + `--output-format streaming-json` (Phase 0 H1/H2: headless works).
- Model polling lifecycle in `WindowStateManager` (start/stop with connection).
- Context Builder / Prompt availability refresh keys (`GrokBuildCLIConnected`, etc.).
- Richer catalog menus; effort levels from session model `_meta` (`high` / `medium` / `low`) if product wants UI.
- Headless tool filtering / yolo policy as needed for CE safety.

## Non-goals

- Recommendation ranking policy (→ Phase 3)
- Extracting a SwiftPM provider package

---

## Exit criteria

- [ ] Headless path used by CE discovery/delegate.
- [ ] Model polling stable; no thrash.
- [ ] Prompt/Context Builder treat Grok Build like Cursor when connected.
- [ ] Tests + preflight commits.
