# MUST READ Before Push

**Audience:** humans and agents about to commit or push this repository.
**Authority:** [`AGENTS.md`](AGENTS.md), [`docs/testing.md`](docs/testing.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), `$rpce-contribution-check`.
**Scope:** hard contracts that fail CI, corrupt shared state, or violate repo policy. Details live in the linked docs.

If you only skim one section, read **§1 Test contract ledger** and **§2 Preflight**.

---

## 1. Test contract ledger (CI `--strict-ledger`)

### MUST

1. **Every root/provider XCTest executable add, rename, consolidate, or remove** updates `Scripts/Fixtures/test-suite-contract-ledger.tsv` in the **same change** as the test code.
2. **Surgical edits only.** Add/replace/delete the exact rows for the affected method IDs. **Never** regenerate or overwrite the curated ledger (do **not** point `inventory --force` at it).
3. Method IDs are exact and case-sensitive:
   - Live XCTest: `RepoPromptTests.<Suite>/testMethod`
   - Ledger: `root/RepoPromptTests.<Suite>/testMethod` (or `provider/…` for the Claude-compatible package)
4. After ledger surgery, reconcile when the environment allows:

```bash
make dev-test-list          # or make dev-provider-test-list
python3 Scripts/test_suite_optimizer.py verify-ledger \
  --ledger Scripts/Fixtures/test-suite-contract-ledger.tsv
```

5. Prefer reviewed contract metadata (`primary_contract_id`, oracle, risk, `execution_tier`, `current_disposition=retain`, …). Do not invent a full-repo format baseline to “fix” CI.

### Why this fails CI

Hosted CI runs:

```text
python3 Scripts/ci_app_test_runner.py … --ledger Scripts/Fixtures/test-suite-contract-ledger.tsv --strict-ledger
```

If the built `.xctest` discovers a suite that is **absent from the ledger**, every app test shard fails immediately with:

```text
ledger is missing discovered suites: ['RepoPromptTests.…']
```

**Adding only `Tests/**/*.swift` is not enough.**

### MUST NOT

- Treat a green focused `make dev-test FILTER=…` as proof the ledger is complete for full CI.
- Leave obsolete method IDs in the ledger after renames/removals.
- Use `retain_pending_review` for new rows (scaffold debt only).

Full workflow: [`docs/testing.md`](docs/testing.md) → “Maintain the contract ledger surgically”.

---

## 2. Contribution preflight (commit / push)

### MUST before every commit

```bash
# Stage only intended paths, then:
.agents/skills/rpce-contribution-check/scripts/preflight.sh commit
```

- Rerun **after any restage** (partial stage included). Commit mode scans **staged index** blobs, not merely the working tree.
- Keep secrets out of commits and out of agent transcripts.

### MUST before every push

```bash
# Clean working tree required:
.agents/skills/rpce-contribution-check/scripts/preflight.sh push
```

Default `push` mode checks: whitespace, secrets (staged + outgoing range), guardrails, clean tree, branch outgoing range. It does **not** run full lint/test/build.

### When PR-ready is required

```bash
.agents/skills/rpce-contribution-check/scripts/preflight.sh pr-ready
```

Use for path-selected heavy local PR evidence (lint/tests/builds/workspace validation as selected). Does not replace release preflight or live smoke.

### MUST obtain explicit user approval before

- Force-push, history rewrite, branch/fork deletion
- Credential rotation or other GitHub-visible destructive mutation
- Stopping or relaunching the **visible** debug app (`make dev-run` / `app stop` / interactive `app relaunch`)

Skill: [`.agents/skills/rpce-contribution-check/SKILL.md`](.agents/skills/rpce-contribution-check/SKILL.md).

---

## 3. Style (SwiftFormat / SwiftLint)

### MUST

- CI **Style** runs `make lint` = **format-check** then **swiftlint --strict**. Untouched-looking style on Grok (or any) new files still fails the job.
- Prefer coordinated style:

```bash
make dev-format-check   # non-mutating
make dev-lint           # format-check + swiftlint strict
# only when mutation is intended:
make dev-format
```

- Install tools via repo entrypoints (`make install-format-tools` / `make dev-install-format-tools`), not ad-hoc random versions when possible.

### MUST NOT

- Run a full-repo format baseline unless explicitly requested.
- Run `make dev-format` “just in case” without intending to rewrite first-party Swift.

---

## 4. Builds, tests, and the developer daemon

### MUST (when daemon is available)

- Prefer **`make dev-*` / `./conductor …`** so lanes (`build`, `debugArtifact`, `liveApp`, `release`, `style`) serialize concurrent agents.
- Prefer the **smallest** relevant focused test/filter for the change; full suite only when the boundary requires it.
- If `job status` shows **global-wait** / waiting for heavy slot: wait on the ticket; do **not** bypass with parallel `swift`/`xcodebuild` that fights the holder.

### MUST NOT

- Assume canceling Xcode cancels a conductor job (inspect `./conductor job list`).
- Start coordinated build/relaunch while another actor is mid-edit on the same checkout.
- Stage or merge local `docs/investigations/*.md` unless intentionally requested (files are unignored for tooling).

Uncoordinated `make build` / `swift test` remain fallbacks when the daemon is unavailable (e.g. no `python3`).

---

## 5. Source layout and product boundaries

### MUST

- Keep `Sources/RepoPromptExecutable` a **one-file** entry shell over `RepoPromptApp`; no feature implementation there.
- Put product flow under `Sources/RepoPrompt/Features/<FeatureName>`; app lifecycle under `Sources/RepoPrompt/App`; cross-cutting substrate under `Sources/RepoPrompt/Infrastructure/<Area>`.
- Shared app/CLI protocol under `Sources/RepoPromptShared`; keep `MCPControlMessages.swift` single-sourced in `Sources/RepoPromptShared/MCP`.
- Tests/fixtures only under `Tests/…` (or package tests), never `Sources/RepoPrompt/**/Tests`.

### MUST NOT

- Recreate legacy top-level `Views`, `ViewModels`, `Services`, `Models`, `Utils`, or `Shared` buckets under the app target.
- Commit `.build/xcode` or treat generated Xcode workspace as release/archive authority (`Package.swift` + conductor + packaging scripts remain authoritative).

Map: [`docs/architecture/source-layout.md`](docs/architecture/source-layout.md).

---

## 6. Signing, debug app, and secrets

### MUST

- Release packaging requires a real `SIGN_IDENTITY`.
- Ad-hoc debug (`ALLOW_ADHOC_SIGNING=1`): **ephemeral** secure storage — API keys / secure permission changes **do not** persist across launches.
- Explicit `SIGN_IDENTITY="Apple Development: …"` (or documented keychain opt-in) when persistent debug Keychain storage is required.
- Never commit API keys, tokens, or private signing material. Preflight secret scans are a backstop, not a license to stage secrets.

### MUST NOT

- Confuse **HTTP Grok (`AIProviderType.grok`)** with **Grok Build CLI (`grokBuild` / ACP)**. Different auth, surfaces, and model raw prefixes (`grokbuild_custom_*` vs xAI API models).

Grok Build maintainer notes: [`.docs/Grok_Build/Usage.md`](.docs/Grok_Build/Usage.md).

---

## 7. Guardrails and notices

### MUST

```bash
make guardrails
```

Includes source-layout guardrails, contributor allowlist checks, and SwiftPM notice inventory vs `Package.resolved`. Dependency / license inventory changes must keep notices consistent.

---

## 8. Pre-push checklist (minimum)

Copy and tick:

- [ ] Diff is intentional; no investigation dumps or secrets staged
- [ ] If XCTest executables changed: **ledger surgically updated** + IDs match suite/method names
- [ ] Style: `make dev-format-check` / `make dev-lint` green for touched Swift (or full CI Style will fail)
- [ ] Focused tests for the changed boundary green (`make dev-test FILTER=…` / provider filter)
- [ ] `preflight.sh commit` after final staging
- [ ] Clean tree + `preflight.sh push`
- [ ] No destructive git/app ops without explicit approval
- [ ] After push: open GitHub Actions for the branch and confirm CI/Style/shards (not only local FILTER green)

---

## 9. Related reading

| Doc | Use when |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | Daemon, run/debug, layout, validation matrix entrypoints |
| [`docs/testing.md`](docs/testing.md) | Ledger surgery, tiers, impacted/shard plans, handoff checklist |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | PR gate, allowlist, contribution policy |
| [`.agents/skills/rpce-contribution-check/`](.agents/skills/rpce-contribution-check/) | Commit/push/pr-ready scripts and validation matrix |
| [`docs/architecture/source-layout.md`](docs/architecture/source-layout.md) | Where code may live |
| [`docs/architecture/provider-plugins.md`](docs/architecture/provider-plugins.md) | Agent provider plugin seam |
| [`.docs/Grok_Build/Usage.md`](.docs/Grok_Build/Usage.md) | Fork Grok Build connect/smoke IDs |

---

## 10. Known CI failure patterns (quick map)

| Symptom | Likely contract break |
| --- | --- |
| `ledger is missing discovered suites: […]` | New/renamed XCTest not in curated ledger (§1) |
| Style job: `N files require formatting` | SwiftFormat/SwiftLint not clean (§3) |
| Guardrails / notice inventory fail | Layout or Package.resolved notices (§5, §7) |
| Secret scan fail | Credential or token in staged/outgoing range (§2, §6) |
| Push preflight: dirty tree | Uncommitted edits after commit (§2) |

When in doubt: fix the contract, do not weaken CI flags locally and assume the fork will pass.
