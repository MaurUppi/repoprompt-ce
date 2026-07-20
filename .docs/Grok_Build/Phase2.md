# Phase 2 — Headless + discovery + deferred product surfaces

**Status:** Planned
**Parent:** [Planning.md](./Planning.md)
**Depends on:** [Phase1.md](./Phase1.md) **COMPLETE** (core Connect + Agent Mode ACP + catalog min)

---

## Goal

Close Phase 1 residuals and reach **Cursor-like parity** beyond the Agent Mode MVP path:

1. Headless / discovery / polling lifecycle
2. Product surfaces Phase 1 intentionally skipped (Oracle, Model Presets, reasoning effort UI)
3. Live RepoPromptCE MCP tool exposure inside Grok ACP sessions

---

## Inherited from Phase 1 (not implemented there)

These were verified or documented as **out of Phase 1 scope** during live UI review (2026-07-20). Phase 2 owns them.

### A. Oracle Model surface

| Observation | Phase 1 stance |
| --- | --- |
| Oracle Model picker lists Claude Code / Codex CLI only — **no Grok Build** | **Expected** Phase 1 non-goal |

**Phase 2 work:**

- Decide product policy: should `ask_oracle` / `oracle_send` / plan-review / Context Builder **analysis** run on Grok Build ACP (or headless)?
- If yes: extend chat/`AIModel` catalog (today has `openCodeCustom` / `cursorCustom`, no Grok Build case) and Oracle routing so Grok appears in the Oracle Model menu when connected.
- If no: keep non-goal and document permanently in user-facing docs (move to Phase 3 docs only).

### B. Model Presets (Oracle Model Presets)

| Observation | Phase 1 stance |
| --- | --- |
| Edit Model Preset → Model lists Claude Code / Codex CLI only — **no Grok** | **Expected** (same `AIModel` / `availableModels` path as Oracle) |

**Phase 2 work:**

- Same catalog/routing as Oracle once policy is yes.
- Ensure presets round-trip stable raw ids (`grokBuild` + `grok-4.5` [+ effort if shipped]).
- MCP “Use Oracle Model Presets” path must resolve Grok without collapsing to Claude/Codex.

### C. Reasoning effort UI (Low / Medium / High)

| Observation | Phase 1 stance |
| --- | --- |
| Context Builder (and Agent catalog) shows **Grok Build → Grok 4.5** only; **no** Low/Medium/High submenu | **Expected** Phase 1 minimum catalog (`AgentModel.grokBuildDefault` only) |

**Phase 0 evidence:** session model list + reasoning efforts `high` / `medium` / `low` in `_meta`; persist base raw **`grok-4.5`** for users.

**Phase 2 work:**

- Expand `AgentModelCatalog.options(for: .grokBuild)` (and menu builders) from discovered `_meta` efforts — Codex/Claude-style nested or flattened options.
- Encode/decode stable selection raw values (base model + effort) for Agent Mode, Context Builder, and role defaults.
- Wire ACP session model / mode config so selected effort is applied (not display-only).
- Agent Models picker and Context Builder Agent should show the same effort set when connected.

### D. Live RepoPromptCE MCP tools in Grok ACP session

| Observation | Phase 1 stance |
| --- | --- |
| Session inject code present (`includeRepoPromptMCPServer: true`, CE `acpJSONObject`) | **Done (code)** |
| Live agent turn saw Grok-user MCP (e.g. `tasks`) but **not** RepoPromptCE tools | Residual, non-blocking for Phase 1 MVP |

**Phase 2 work:**

- Confirm handshake under **stable signed** debug CLI install (not only ad-hoc + manual symlink).
- Diagnose spawn/handshake (empty `~/.grok/logs/mcp/RepoPromptCE.stderr.log`, tools not listed).
- Prove one read-only CE MCP tool call from a Grok Build Agent Mode session (e.g. `windows` / `tree`).
- Document any Grok-side limits vs Cursor MCP inject.

### E. UI smoke (non-ad-hoc)

- Agent Models picker smoke after **Apple Development** (or other persistent) signing relaunch — MCP already proved selection; UI smoke still useful for release confidence.

---

## Scope (original Phase 2 + above)

### Headless + discovery

- `GrokBuildACPHeadlessAgentProvider` and/or `grok -p` + `--output-format streaming-json` (Phase 0 H1/H2).
- Model polling lifecycle in `WindowStateManager` (start/stop with connection).
- Context Builder / Prompt availability refresh keys (`GrokBuildCLIConnected`, etc.).
- Prompt/`AIModel` availability refresh when Grok connects/disconnects (shared with Oracle/Presets if those ship).
- Headless tool filtering / yolo policy as needed for CE safety.

### Catalog parity

- Richer catalog menus; **effort levels** from session model `_meta` (see **C** above).
- Keep default user-facing model raw **`grok-4.5`**.

### Deferred product surfaces (from Phase 1 review)

- Oracle Model + Model Presets (**A**, **B**) if product accepts Grok as oracle backend.
- Live MCP tool proof (**D**).

---

## Non-goals

- Recommendation ranking / onboarding wizard polish (→ Phase 3)
- Extracting a SwiftPM provider package (→ Phase 3 optional)
- Changing HTTP `GrokProvider` (xAI API keys) or conflating it with Grok Build CLI
- `x.ai/*` ACP extensions unless required for effort/MCP
- Claude plugin package shape

---

## Exit criteria

- [ ] Headless path used by CE discovery/delegate (or explicit deferral documented).
- [ ] Model polling stable; no thrash on connect/disconnect.
- [ ] Reasoning effort options available in Agent Models + Context Builder when Grok reports them.
- [ ] Oracle Model + Model Presets either list Grok when connected **or** documented permanent non-goal with user-facing note.
- [ ] Live RepoPromptCE MCP tool callable from a Grok Build Agent Mode session (or root-caused + filed follow-up).
- [ ] Prompt/Context Builder treat Grok Build like Cursor when connected (availability + menus).
- [ ] Tests + contribution preflight commits.

---

## Suggested implementation order

1. **C** Reasoning effort catalog + ACP apply (high user-visible value; reuses Phase 0 `_meta`).
2. **D** Live MCP handshake proof (unblocks “full Cursor-parity” claim).
3. Headless + polling lifecycle.
4. **A/B** Oracle + Model Presets (product decision gate first).
5. UI smoke under persistent signing.
