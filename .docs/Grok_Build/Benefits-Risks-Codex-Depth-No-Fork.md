# Benefits & risks: Codex-depth Grok Build **without modifying Grok Build source**

**Date:** 2026-07-21
**Constraint:** Integrate only inside **RepoPrompt CE** (and user-level config CE may write). Do **not** fork/patch [xai-org/grok-build](https://github.com/xai-org/grok-build).
**Upstream:** Grok Build is open source (Rust CLI/TUI + agent runtime; Apache-2.0 first-party; **external PRs not accepted**).
**Baseline gaps:** [Gap-vs-Codex-Claude.md](./Gap-vs-Codex-Claude.md)
**Rejected:** embedding [xai-sdk-python](./Research-xai-sdk-python.md)

---

## 1. What “Codex integration depth” can mean under the constraint

Codex depth in CE is **app-owned product + runtime glue** around a **local agent**, not ownership of Codex’s protocol. Under “no Grok source changes,” depth splits cleanly:

| Tier | Meaning | Needs Grok source change? | Realistic ceiling |
| --- | --- | --- | --- |
| **T1 — Product parity** | Recommendations, onboarding, probes, catalog defaults, changelog, icons, tests | **No** | Full CE product parity with how Codex is *surfaced* |
| **T2 — Contract-faithful ACP** | Better use of documented ACP + CLI flags/config (`session/*`, effort, MCP inject, permission modes, resume) | **No** (read-only use of public surface + OSS as reference) | **Cursor+** / partial Codex *UX*, not app-server |
| **T3 — x.ai extension surface** | Consume Grok-specific ACP methods (`x.ai/fs/*`, `x.ai/git/*`, session fork/rewind, sandbox profiles, richer permissions) **if** exposed over stdio today | **No** if already in agent protocol; CE implements client | High value, higher churn |
| **T4 — True Codex protocol twin** | App-server, steer-ack, computer-use goals, Codex-native session controller | Would require **different product** or forking Grok | **Out of scope** (Class A in Gap doc) |

**Important reframe:** “Codex depth” achievable without forking Grok ≈ **make Grok as first-class in CE as Codex is in CE’s product shell**, while the **agent engine remains Grok’s binary**. It does **not** mean reimplementing `CodexNativeSessionController` for Grok.

Open source changes the game for **T2/T3**: CE can **read** `xai-grok-shell`, user-guide, and ACP extension lists to wire features correctly, still without shipping a fork.

---

## 2. What open source enables (still without modifying upstream)

| Capability | Closed binary only | With [grok-build](https://github.com/xai-org/grok-build) OSS |
| --- | --- | --- |
| Discover `session/set_model`, modes, MCP inject | Probe + reverse engineer | **Read source + docs** (`15-agent-mode.md`, shell crates) |
| Map permission modes / sandbox profiles | Guess from flags | Align CE prefs to documented modes (`default`, `acceptEdits`, `bypassPermissions`, sandbox profiles) |
| `~/.grok/config.toml` MCP install helper (G-15) | Trial-and-error | **Schema-known** `[mcp_servers.*]`, timeouts, env |
| Session resume / disk layout | Opaque | Documented `~/.grok/sessions/…` (resume/continue/fork) |
| Extension methods `x.ai/*` | Partial discovery via `initialize` | Catalog from docs; implement selectively in CE |
| Bug ownership | “Is it us or them?” hard | Bisect against SOURCE_REV / released binary behavior |
| Contribute fixes upstream | N/A | **External contributions not accepted** — still no CE patches in-tree |

**Does not enable:** CE-controlled patches to Grok runtime, custom app-server, or guaranteed stable private APIs beyond what the released binary supports.

---

## 3. Benefits (CE-only, no Grok source changes)

### 3.1 High benefit / low risk (T1 — close Gap P0/P1 product stubs)

| Benefit | Why it matters | Gap IDs |
| --- | --- | --- |
| **Honest provider status** | Connect Grok stops lying in wizards (`grokBuildAvailable: false`) | G-01, G-02 |
| **Recommendations & onboarding** | Solo-Grok users get chat/Oracle/Context Builder defaults like Codex users | G-10–G-13 |
| **Startup probe** | Stale “Connected” after uninstall/PATH break | G-17 |
| **Best-practice candidates** | Product can prefer `grok-4.5:medium` when policy allows | G-12 |
| **Regression tests** | Lock identity, effort raws, Oracle IDs without live xAI cost for unit pieces | G-14 |
| **Changelog / discoverability** | Users learn Grok Build exists as peer CLI provider | G-20, G-21 |

**Codex-depth claim for T1:** Matches how Codex is **recommended and trusted** in CE UI — the part users feel as “first-class.”

### 3.2 Medium–high benefit (T2 — deepen existing ACP path)

| Benefit | Mechanism without forking Grok |
| --- | --- |
| **Richer permission UX** | Map CE Full Access → `--always-approve` / `bypassPermissions`; surface `acceptEdits`-like modes if ACP/session supports |
| **MCP config install** | Optional `GrokBuildIntegrationConfiguration` writing `~/.grok/config.toml` `[mcp_servers.RepoPromptCE]` like Codex TOML helper |
| **Timeouts** | Document/set `tool_timeout_sec`, `GROK_MCP_*` env analogs of Codex long timeout (evidence-based, not invent protocol) |
| **Session resume polish** | Use ACP load + documented session IDs; optionally surface session dir diagnostics |
| **Headless Oracle quality** | Align headless flags (`--effort`, tool disallow) with Grok docs for text-only Oracle |
| **Error classification** | PATH / auth / ACP / MCP buckets (Codex lesson) using real Grok messages |

**Codex-depth claim for T2:** Operational robustness and MCP ecosystem parity **as far as Grok’s public config allows** — still ACP, not app-server.

### 3.3 Optional upside from OSS + public extensions (T3)

Documented ACP extensions (`x.ai/fs/*`, git, worktree, terminal, rewind, compact, auth URL flow) could, **if** CE chooses to implement clients:

| Benefit | Risk trade (see §4) |
| --- | --- |
| IDE-like FS/git panels driven by agent | Large surface; version churn |
| Worktree-aware resume | High product value; complex lifecycle |
| Auth URL/code flow in-app | Better than “run grok login in terminal” |
| Thought/plan streams already partly generic | Better Agent Mode UX |

These are **optional product bets**, not required to fix T1 stubs.

### 3.4 Strategic / non-technical benefits

| Benefit | Note |
| --- | --- |
| **Architecture purity** | Keeps single ACP control plane (Cursor/OpenCode/Grok); no Python/xAI SDK sidecar |
| **Vendor boundary** | CE owns UX; Grok owns agent intelligence — same as Codex CLI model |
| **OSS auditability** | Security review of MCP inject, sandbox, permission pipeline against published docs/source |
| **Marketing parity** | “Grok Build as first-class agent” without claiming to ship Grok itself |

---

## 4. Risks (under no-fork constraint)

### 4.1 Ceiling / false parity (most important)

| Risk | Detail | Mitigation |
| --- | --- | --- |
| **False “Codex depth” marketing** | Cannot match app-server, steer, goal workflows, Codex session controller LOC | Define success as **T1+T2 product parity**, not protocol twin; keep Class A non-goals |
| **Asymmetric depth forever** | Codex will always have CE-specific native knobs Grok won’t | Document expected asymmetry in Gap Class A |
| **x.ai/* lock-in** | Extension methods may change without SemVer for hosts | Gate T3 behind capability discovery from `initialize`; degrade to base ACP |

### 4.2 Stability / support (OSS does not mean stable host API)

| Risk | Detail | Mitigation |
| --- | --- | --- |
| **Binary ≠ tree** | OSS is monorepo sync (`SOURCE_REV`); install script ships `grok` releases that may lag or differ | Pin integration tests to **released** `grok --version`; treat source as reference only |
| **No external contributions** | Cannot land CE-needed fixes upstream easily | Workarounds in CE; feature-detect; escalate via support channels not PR |
| **Rapid CLI churn** | Models, efforts, MCP defaults, permission names | Versioned probes; tolerant parsing; no hardcode of `0.2.x` in product |
| **Dual transport** | `stdio` vs `serve` WebSocket vs headless `-p` | Stay on stdio ACP for Agent Mode; don’t sprawl |

### 4.3 Product / UX risks of *over*-integrating

| Risk | Detail | Mitigation |
| --- | --- | --- |
| **Permission double stack** | CE Full Access **and** Grok sandbox **and** hooks **and** MCP policy | Single mental model: document which layer wins; default conservative |
| **MCP double registration** | ACP inject **plus** `~/.grok/config.toml` install → duplicate servers | Prefer inject for Agent Mode; config install only for standalone TUI if needed |
| **Tool grant mismatch (G-16)** | Cursor-sized MCP grants vs Codex-wide | Expand grants only with evidence of missing tools |
| **Three Groks** | HTTP API Grok vs Build CLI vs cloud tools | UI copy: “Grok Build (CLI)” vs “Grok (xAI API)” |
| **Recommendation bias** | Promoting Grok when Codex is still best default for many workflows | Policy: optional / after Codex/Claude, not replacing Best Practice without data |

### 4.4 Security / data plane

| Risk | Detail | Mitigation |
| --- | --- | --- |
| **Always-approve / yolo** | Codex-like Full Access maps to dangerous Grok modes | Warning UX; never default Full Access for new users |
| **Writing user `config.toml`** | Malformed or broad MCP env secrets | Atomic write, backup, narrow server entry, no secret in world-readable paths |
| **Agent tools on host** | Grok can shell/edit; sandbox profiles reduce but don’t eliminate risk | Prefer sandbox profiles when documented; keep CE MCP approval overlays |
| **Session data on disk** | `~/.grok/sessions` holds prompts/tools | Don’t scrape/upload; optional local diagnostics only |

### 4.5 Engineering / maintenance

| Risk | Detail | Mitigation |
| --- | --- | --- |
| **T3 cost explosion** | Implementing many `x.ai/*` methods = large permanent surface | Prioritize T1 then selective T2; T3 only with ROI |
| **Test matrix** | Live Grok needs login + network | Unit tests offline; smoke opt-in (`conductor smoke --agent-run` pattern) |
| **Ad-hoc debug signing** | Ephemeral secure storage confuses permission persistence | Document; prefer Development identity for real permission tests |
| **Opportunity cost** | Deep Grok polish vs other CE work | Cap at Gap G-01–G-17 + thin IntegrationConfiguration |

### 4.6 Legal / compliance (light)

| Risk | Detail |
| --- | --- |
| **Apache-2.0 + third_party** | Reading OSS is fine; do not vendor Grok crates into CE without notice review |
| **No CE fork of grok-build** | Constraint already avoids redistribution issues of a modified agent |

---

## 5. Benefit–risk by Gap backlog (decision aid)

| Gap | Benefit if done CE-only | Risk | Recommend |
| --- | --- | --- | --- |
| G-01, G-02 | High (correctness) | Low | **Do** |
| G-10–G-13 | High (first-class feel) | Medium (default policy fights) | **Do** with careful priority order |
| G-14 | High long-term | Low | **Do** |
| G-17 | Medium–high | Low | **Do** |
| G-15 IntegrationConfiguration | Medium (TUI parity) | Medium (config corruption, dup MCP) | **Do only** with schema from docs/OSS; opt-in |
| G-16 wider MCP grants | Medium | Medium (security) | **Evidence-gated** |
| G-20–G-22 polish | Medium | Low | **Do** at ship time |
| T3 `x.ai/*` client features | High if used | High (churn, scope) | **Selective later** |
| T4 Codex protocol twin | Illusory | Very high | **Don’t** |

---

## 6. Recommended posture

**Agreed execution (2026-07-21):**

| Track | Decision |
| --- | --- |
| **T1 + T2** | **Priority** — [Phase4.md](./Phase4.md) implements G-01, G-02, G-10–G-14, G-17 + permission mapping notes |
| **T3** (`x.ai/*` clients) | **Shelved** — record only; revisit after T1/T2 with ROI |
| **T4** (Codex protocol twin) | **Shelved** — permanent non-goal unless architecture re-targets |
| Phase 3 leftovers | **Migrated** into Phase 4 |

**Do (Codex-depth *in CE product terms*, no Grok source changes):**

1. Close **T1** gaps (status, recommendations, probe, tests, changelog).
2. Use **open source + user guide** as a **read-only contract library** for T2 (permissions mapping, MCP config schema, session semantics, effort levels).
3. Keep runtime on **released `grok agent stdio` ACP** already in CE.

**Don’t:**

1. Fork or patch grok-build for CE features.
2. Claim protocol-level Codex parity.
3. Embed xAI cloud SDK as a substitute for agent depth.
4. Auto-write broad `~/.grok/config.toml` without backups and narrow scope.

**Net:**
Under the no-source-change constraint, **most of the remaining “Codex integration depth” users notice is CE product wiring (T1), not missing Grok code.** Open source **raises the ceiling of safe T2/T3 work** (config, permissions, extensions) and **lowers reverse-engineering risk**, but **does not remove** release churn, non-contributable upstream, or the hard ceiling that Grok is ACP, not Codex app-server.

---

## 7. One-line summary

**Benefits are concentrated in CE-side first-class product + faithful ACP/config use (OSS as documentation); risks are false parity, CLI churn, permission/MCP double stacks, and scope creep into `x.ai/*` — none of which require modifying Grok Build source, and none justify forking it.**
