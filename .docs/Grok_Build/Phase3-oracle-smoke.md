# Phase 3 — Live Oracle smoke (Grok Build)

**Date:** 2026-07-21
**Host:** local CE debug (`ALLOW_ADHOC_SIGNING=1 make dev-run`)
**CLI:** `repoprompt_ce_cli_debug` → DebugApps `repoprompt-mcp`
**Bundle domain:** `com.pvncher.repoprompt.ce.debug`
**Parent:** [Phase3.md](./Phase3.md), [Usage.md](./Usage.md)

---

## Goal

Prove Oracle (`oracle_send`) can complete a turn using **Grok Build** as `models.planning_model`, not HTTP xAI Grok.

---

## Preconditions

| Check | Result |
| --- | --- |
| App running + MCP | OK (`windows` listed) |
| `GrokBuildCLIConnected` | `1` (UserDefaults; Connect done previously) |
| Workspace | Switched to `multi_report` (non-default project) |

---

## Steps

### 1. Set Oracle model

```bash
rpce-cli-debug -w 1 -c app_settings -j '{
  "op":"set",
  "key":"models.planning_model",
  "value":"grokbuild_custom_grok-4.5:low"
}'
```

**Observed:**

```text
Old → New: "codex_cli_gpt-5.6-sol-high" → "grokbuild_custom_grok-4.5:low"
```

### 2. Confirm

```bash
rpce-cli-debug -w 1 -c app_settings -j '{"op":"get","key":"models.planning_model"}'
```

**Observed:** value `"grokbuild_custom_grok-4.5:low"`.

### 3. Workspace

```bash
rpce-cli-debug -w 1 -e 'workspace switch multi_report'
```

### 4. Oracle turn

```bash
rpce-cli-debug -w 1 -c oracle_send -j '{
  "message":"Reply exactly with CE_GROK_ORACLE_SMOKE_OK and stop. Do not use tools.",
  "mode":"chat",
  "new_chat":true
}'
```

---

## Result

| Field | Value |
| --- | --- |
| Status | **PASS** |
| Progress | `oracle_send [starting]` → `[complete]` |
| Chat | `untitled-chat-E26CF8` · mode `chat` |
| Assistant text | **`CE_GROK_ORACLE_SMOKE_OK`** |
| Duration (approx.) | ~few seconds after start |

---

## Notes

1. Oracle path uses `GrokBuildCLIProvider` (headless ACP, no RepoPrompt MCP inject).
2. Effort encoded in model raw (`:low`); launch strips effort for `-m`, headless applies `session/set_mode`.
3. `app_settings op=options` may not always surface Grok rows in truncated lists when catalog is cold; **set by explicit raw value still works** when Grok Build is connected.
4. Distinct from Agent Mode MCP tool smoke (`CE_GROK_MCP_OK` in Phase 2).

---

## Follow-ups (optional)

- UI-only Oracle picker smoke after non-ad-hoc relaunch.
- Model Preset create/save round-trip with `grokbuild_custom_*`.
- User-facing changelog entry when shipping in a release.
