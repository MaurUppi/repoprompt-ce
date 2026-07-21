# Grok Build in RepoPrompt CE — Usage

**Date:** 2026-07-21
**Audience:** local CE debug / maintainers
**Related:** [Planning.md](./Planning.md), [Phase1.md](./Phase1.md)–[Phase4.md](./Phase4.md)

---

## What is wired

| Surface | Status | Notes |
| --- | --- | --- |
| **CLI Providers → Connect** | Done | PATH + `grok agent stdio` ACP probe; auth via `grok login` / `cached_token` |
| **Agent Models** | Done | Select **Grok Build** + **Grok 4.5 High / Medium / Low** |
| **Context Builder Agent** | Done | Same agent/model catalog as Agent Mode; recommendation fallback after Cursor |
| **Agent Mode multi-turn ACP** | Done | Streamed turns; optional RepoPrompt MCP tools |
| **Oracle Model** | Done (Phase 3) | Chat/plan/review oracle via headless ACP |
| **Model Presets** | Done (Phase 3) | Same `AIModel` list as Oracle when connected |
| **Recommendations / onboarding** | Done (Phase 4 T1) | Status snapshot, wizard grids, chat/Oracle & Context Builder ranking |
| **Startup Connect probe** | Done (Phase 4 G-17) | Cached Grok ACP discovery when previously Connected |
| **HTTP Grok (xAI API keys)** | Unchanged | `AIProviderType.grok` — **not** Grok Build |

Stable IDs:

- Agent kind: `grokBuild`
- Agent model raws: `grok-4.5`, `grok-4.5:high`, `grok-4.5:medium`, `grok-4.5:low`
- Oracle/chat model raws: `grokbuild_custom_grok-4.5:high|medium|low`
- Recommendation default planning raw when only Grok is ready: `grokbuild_custom_grok-4.5:medium`

---

## Prerequisites

1. **Grok Build CLI** installed and on login-shell PATH (also `~/.local/bin`, `~/.grok/bin` for GUI apps).
   - Install: `curl -fsSL https://x.ai/cli/install.sh | bash` (see [x.ai/cli](https://x.ai/cli) / [xai-org/grok-build](https://github.com/xai-org/grok-build)).
2. Authenticated: `grok login` (CE uses ACP `authenticate` / `cached_token`). Non-browser hosts may use `XAI_API_KEY` for the CLI itself; CE Connect still keys off CLI/ACP success, not Keychain xAI keys for **Grok Build**.
3. CE debug app running with MCP enabled (Settings → MCP).
4. Debug CLI resolvable, e.g.:

```bash
"$HOME/Library/Application Support/RepoPrompt CE/repoprompt_ce_cli_debug" --version
# or linked as /usr/local/bin/rpce-cli-debug after make install-debug-cli
```

Debug packaging without a signing identity:

```bash
ALLOW_ADHOC_SIGNING=1 make dev-run
```

Ad-hoc builds use **ephemeral secure storage** (Connect/permissions may not persist across launches). `UserDefaults` flags such as `GrokBuildCLIConnected` can still persist.

---

## Connect Grok Build

1. Open **Settings → Agent Mode → CLI Providers**.
2. Find **Grok Build** → **Connect**.
3. Expect: Connected badge, model availability, Permissions (Default / Full Access).

If Connect fails:

| Symptom | Likely cause |
| --- | --- |
| CLI not found | Install `grok`; fix PATH for GUI (login shell + supplemental bins) |
| Auth / re-login | Run `grok login` in a terminal, retry Connect |
| No ACP / stdio | Update Grok Build; `grok agent stdio --help` should mention stdio |

After Connect succeeds once, CE may **re-probe** Grok on context-builder provider validation (ACP model discovery) so a stale Connected flag after uninstall/PATH break is less likely.

---

## Agent Mode

1. **Agent Models** (or composer agent picker) → **Grok Build** → effort (**High** / **Medium** / **Low**).
2. Send a message; assistant text should stream.
3. With MCP up, Grok can call RepoPrompt tools (e.g. tree/windows) after session inject.

MCP debug CLI smoke (Agent Mode, not Oracle):

```bash
rpce-cli-debug -w 1 -e 'workspace switch multi_report'
rpce-cli-debug -w 1 -c agent_run -j '{
  "op":"start",
  "model_id":"grokBuild:grok-4.5:low",
  "session_name":"Grok Agent smoke",
  "message":"Reply exactly with CE_GROK_BUILD_SMOKE_OK and stop.",
  "detach":true
}'
# then agent_run op=wait with returned session_id
```

---

## Oracle Model + Model Presets

1. Connect Grok Build (above).
2. **Settings → Agent Models → Oracle Model** → **Grok Build** → effort.
3. Or set via MCP:

```bash
rpce-cli-debug -w 1 -c app_settings -j '{
  "op":"set",
  "key":"models.planning_model",
  "value":"grokbuild_custom_grok-4.5:low"
}'
```

4. Oracle turn (MCP):

```bash
rpce-cli-debug -w 1 -e 'workspace switch multi_report'   # project workspace, not Default
rpce-cli-debug -w 1 -c oracle_send -j '{
  "message":"Reply exactly with CE_GROK_ORACLE_SMOKE_OK and stop. Do not use tools.",
  "mode":"chat",
  "new_chat":true
}'
```

Oracle uses **headless ACP** (`GrokBuildCLIProvider`): no RepoPrompt MCP inject into that session; text-only prompt suffix. Distinct from Agent Mode (which can inject RepoPromptCE tools).

Model Presets: create/edit a preset and choose a **Grok Build** model the same way as other CLI models (value prefix `grokbuild_custom_`).

Live evidence: [Phase3-oracle-smoke.md](./Phase3-oracle-smoke.md).

---

## Context Builder Agent

**Context Builder Agent** (discovery) can use Grok Build + effort when connected.
**Context Builder analysis** still uses the **Oracle Model** (may be Grok Build after Phase 3).

Recommendation order when choosing a default agent (Phase 4):

**Codex → Claude Code → Cursor → Grok Build**

Grok is only recommended for Context Builder when the preferred providers are not ready.

---

## Recommendations & onboarding (Phase 4)

When Grok Build is Connected and verified:

| Surface | Behavior |
| --- | --- |
| Provider status grids | Show **Grok Build** alongside Claude / Codex / Cursor / OpenAI |
| Chat / Oracle backend cards | Offer **Grok Build** (`grokbuild_custom_grok-4.5:medium`) |
| Chat default priority | Codex → OpenAI API → Claude Code → **Grok** (Grok is default only if others are not ready) |
| MCP agent role defaults | Grok can appear as a late fallback candidate (explore/engineer/pair/design) |

Grok does **not** displace Codex as the preferred Best Practice default when Codex is ready.

---

## Permission levels (Phase 4 T2)

| CE setting | Effect |
| --- | --- |
| Default | Grok may prompt for tool approval via ACP |
| Full Access | CE auto-approves Grok ACP tool permission requests (similar intent to Grok `--always-approve` / `bypassPermissions`) |

Sandbox profiles and fine-grained Grok rules remain in Grok’s own config/TUI (`~/.grok`); CE does not fork Grok Build to re-host them. Agent Mode still injects RepoPrompt MCP through the ACP session when configured.

---

## Identity notes (MCP inject)

Grok may present clients as:

- Parent process: `grok` or versioned `grok-<version>-…` (prefix match only; **no version hardcode** in product code)
- MCP `clientInfo.name`: `grok-shell-RepoPromptCE`

CE maps these to family **`grok`** for Agent Mode policy routing (`MCPClientIdentity`).

---

## Troubleshooting

| Issue | Check |
| --- | --- |
| Oracle/Presets missing Grok Build | Connect CLI Providers; relaunch if ad-hoc; confirm `GrokBuildCLIConnected` |
| Agent Mode works, Oracle fails | Confirm `models.planning_model` is `grokbuild_custom_…`; disable conflicting Model Presets if needed |
| MCP tools missing in Agent Mode | App running + MCP on; identity family `grok`; see [Phase2.md](./Phase2.md) §D |
| Confused with xAI API Grok | Settings API keys **Grok (xAI)** ≠ **Grok Build** CLI card |
| Recommendations ignore Grok | Connect + wait for startup probe; ensure recommendation filter includes Grok Build; only Grok becomes *default* when higher-priority backends are not ready |
| Stale Connected after uninstall | Restart app so G-17 probe can clear verified state; re-Connect after fixing PATH/`grok` |

---

## What is not in CE (yet)

| Item | Notes |
| --- | --- |
| Writing `~/.grok/config.toml` MCP install helper | Optional Phase 4 G-15; Agent Mode uses ACP inject |
| Grok ACP extensions (`x.ai/fs/*`, git panels, …) | Shelved T3 |
| Codex-style app-server runtime | Shelved T4 / non-goal |
| xAI Python SDK | Rejected for Agent Mode; see [Research-xai-sdk-python.md](./Research-xai-sdk-python.md) |

---

## Phase map

| Phase | File |
| --- | --- |
| Plan outline | [Planning.md](./Planning.md) |
| 0 Probe | [Phase0.md](./Phase0.md), [Phase0-evidence.md](./Phase0-evidence.md) |
| 1 MVP | [Phase1.md](./Phase1.md) |
| 2 Effort + MCP | [Phase2.md](./Phase2.md) |
| 3 Oracle/Presets | [Phase3.md](./Phase3.md) |
| Live Oracle smoke | [Phase3-oracle-smoke.md](./Phase3-oracle-smoke.md) |
| Gap vs Codex/Claude | [Gap-vs-Codex-Claude.md](./Gap-vs-Codex-Claude.md) |
| Phase 4 (T1/T2 first-class) | [Phase4.md](./Phase4.md) |
| Codex-depth benefits/risks | [Benefits-Risks-Codex-Depth-No-Fork.md](./Benefits-Risks-Codex-Depth-No-Fork.md) |
| xai-sdk research | [Research-xai-sdk-python.md](./Research-xai-sdk-python.md) |
