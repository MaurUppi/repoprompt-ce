# RepoPrompt CE (fork)

[![CI](https://github.com/MaurUppi/repoprompt-ce/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/MaurUppi/repoprompt-ce/actions/workflows/ci.yml?query=branch%3Amain)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS%2026%2B-black)

**Fork of [repoprompt/repoprompt-ce](https://github.com/repoprompt/repoprompt-ce)** with **Grok Build** as a first-class Agent Mode / CLI provider (ACP), alongside Codex, Claude Code, Cursor, and OpenCode.

Upstream remains a free, open-source native macOS app for context engineering and agent orchestration. This fork keeps that base and adds Grok Build integration docs and product wiring.

---

## Grok Build (this fork)

Grok Build is SpaceXAI’s terminal coding agent ([xai-org/grok-build](https://github.com/xai-org/grok-build)). In this CE tree it is wired like **Cursor CLI** (ACP `grok agent stdio`), **not** the HTTP xAI API provider (`AIProviderType.grok`).

### What works

| Surface | Notes |
| --- | --- |
| **CLI Providers → Connect** | PATH + `grok agent stdio` probe; auth via `grok login` / ACP `cached_token` |
| **Agent Models** | **Grok Build** + effort **High / Medium / Low** |
| **Agent Mode** | Multi-turn ACP; optional RepoPrompt MCP tool inject |
| **Oracle / Model Presets** | Headless ACP (`grokbuild_custom_*`); no MCP inject on Oracle path |
| **Context Builder Agent** | Same catalog when Connected; recommendation fallback after Cursor |
| **Recommendations** | Status grids + chat/Oracle cards; default only if higher-priority backends are off |

### Quick start

1. Install Grok Build and log in:

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
grok login
# ensure GUI apps see it: ~/.local/bin and/or ~/.grok/bin on PATH
```

2. Build and launch CE debug (no Apple Development identity):

```bash
ALLOW_ADHOC_SIGNING=1 make dev-run
# or: ALLOW_ADHOC_SIGNING=1 ./conductor app relaunch
```

Ad-hoc builds use **ephemeral** secure storage (Connect/permissions may not persist). Prefer a stable `SIGN_IDENTITY="Apple Development: …"` when you need Keychain persistence.

3. In the app: **Settings → Agent Mode → CLI Providers → Grok Build → Connect**.
   Then pick **Grok Build** under Agent Models / Oracle Model (effort High/Medium/Low).

4. Optional debug CLI smoke (app running + MCP on; workspace not Default):

```bash
# Agent Mode
rpce-cli-debug -w 1 -c agent_run -j '{
  "op":"start",
  "model_id":"grokBuild:grok-4.5:low",
  "session_name":"Grok smoke",
  "message":"Reply exactly with CE_GROK_BUILD_SMOKE_OK and stop.",
  "detach":true
}'

# Oracle (planning model)
rpce-cli-debug -w 1 -c app_settings -j '{
  "op":"set",
  "key":"models.planning_model",
  "value":"grokbuild_custom_grok-4.5:low"
}'
rpce-cli-debug -w 1 -c oracle_send -j '{
  "message":"Reply exactly with CE_GROK_ORACLE_SMOKE_OK and stop. Do not use tools.",
  "mode":"chat",
  "new_chat":true
}'
```

### IDs (do not confuse)

| Kind | Value |
| --- | --- |
| Agent kind | `grokBuild` |
| Agent model raws | `grok-4.5`, `grok-4.5:high\|medium\|low` |
| Oracle / chat raws | `grokbuild_custom_grok-4.5:high\|medium\|low` |
| HTTP xAI Grok | Settings API keys **Grok (xAI)** — separate from **Grok Build** |

### Permissions

| CE level | Meaning |
| --- | --- |
| **Default** | Grok may prompt for tool approval over ACP |
| **Full Access** | CE auto-approves ACP tool permissions (similar intent to Grok `--always-approve` / `bypassPermissions`) |

Sandbox profiles and fine-grained rules stay in Grok (`~/.grok`); CE does not re-host them.

### Docs in this tree

| Doc | Purpose |
| --- | --- |
| [`.docs/Grok_Build/Usage.md`](.docs/Grok_Build/Usage.md) | Full maintainer usage & troubleshooting |
| [`.docs/Grok_Build/Planning.md`](.docs/Grok_Build/Planning.md) | Phase index |
| [`.docs/Grok_Build/Phase4.md`](.docs/Grok_Build/Phase4.md) | T1/T2 first-class product work |
| [`.docs/Grok_Build/Gap-vs-Codex-Claude.md`](.docs/Grok_Build/Gap-vs-Codex-Claude.md) | Gap vs Codex/Claude |
| [`.docs/Grok_Build/Phase3-oracle-smoke.md`](.docs/Grok_Build/Phase3-oracle-smoke.md) | Live Oracle smoke evidence |

### Not in scope (yet)

- Optional write of `~/.grok/config.toml` MCP install helper (Agent Mode uses ACP inject)
- Grok ACP extensions (`x.ai/fs/*`, …) and Codex app-server parity
- Embedding the xAI Python cloud SDK for Agent Mode

---

<details>
<summary><strong>Official RepoPrompt CE README</strong> (upstream overview, install, features, contributor docs)</summary>

# RepoPrompt CE

[![CI](https://github.com/repoprompt/repoprompt-ce/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/repoprompt/repoprompt-ce/actions/workflows/ci.yml?query=branch%3Amain)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS%2026%2B-black)

**A free, open-source native macOS app and agent orchestrator for context engineering.**

RepoPrompt CE helps coding agents understand your codebase before they act. It
assembles focused, reviewable context from files, CodeMaps, repository
structure, and Git diffs, then hands that context to AI tools and CLI agents.

RepoPrompt CE also builds an agent harness around its bundled MCP server.
Connect MCP-compatible clients and CLI agents to search repositories, inspect
files, curate context, run agent sessions, and orchestrate work through a shared
native macOS interface.

## Get Started

Choose one of these setup paths. You do not need to open Xcode.

### Install with Homebrew

For the signed and notarized public app, use the dedicated RepoPrompt CE
Homebrew tap:

```bash
brew tap repoprompt/repoprompt-ce
brew install --cask repoprompt-ce
```

This installs `/Applications/RepoPrompt CE.app` from the
[`repoprompt/homebrew-repoprompt-ce`](https://github.com/repoprompt/homebrew-repoprompt-ce)
tap. The cask consumes the promoted public updater ZIP from
[`repoprompt/repoprompt-ce-updates`](https://github.com/repoprompt/repoprompt-ce-updates);
it does not build from source. Source-build paths remain below for contributors
and local development.

### Build and launch locally

For development and quick evaluation, double-click
[`Launch RepoPrompt CE.command`](Launch%20RepoPrompt%20CE.command) in Finder.

The launcher requires Python 3, builds RepoPrompt CE through the coordinated
developer daemon, opens the debug app, and keeps a small terminal window
available for rebuild, status, and stop controls. It does not provide an
uncoordinated no-Python fallback because lifecycle actions validate the exact
debug executable path.

The debug launcher uses an available `Apple Development:` signing identity. If
your Mac does not have one, run the same debug app from Terminal with explicit
ad-hoc signing:

```bash
ALLOW_ADHOC_SIGNING=1 ./conductor app relaunch
```

Ad-hoc debug builds use in-memory secure storage, so saved API keys and secure
permission changes do not persist across launches. For persistent debug
Keychain storage, pass a stable Apple Development identity explicitly:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./conductor app relaunch
```

For a stable locally signed app under `/Applications`, use the local production
installer below. Its self-signed identity is separate from the debug launcher's
Apple Development signing path.

> **Note:** If you use the debug app to modify RepoPrompt CE itself, validation
> flows that launch the app or run live smoke checks may rebuild and relaunch it.
> Expect the debug app to restart while those checks run.

| Key | Action                                      |
| --- | ------------------------------------------- |
| `r` | Rebuild and relaunch                        |
| `s` | Show app status                             |
| `x` | Stop the app                                |
| `q` | Close the launcher without stopping the app |

### Install a local production build

For a release-mode app under `/Applications`, install Python 3 and double-click
[`Install RepoPrompt CE Local Production.command`](Install%20RepoPrompt%20CE%20Local%20Production.command)
in Finder. The Finder launcher uses the coordinated developer daemon.

The installer builds RepoPrompt CE from source and replaces any existing
`/Applications/RepoPrompt CE.app` using a dedicated self-signed certificate
trusted only on your Mac. macOS may ask you to approve the certificate.

The resulting app is local-only. It is not notarized and should not be copied to
another Mac or redistributed.

### Source-build requirements

- macOS 26 or later
- Xcode 26, or matching Command Line Tools with the macOS 26 SDK

### Develop in Xcode

Generate and open the disposable contributor workspace with:

```bash
make xcode
```

In Xcode 26.3, use `RepoPrompt CE App` for the packaged debug app,
`RepoPrompt CE MCP` for the coordinated MCP executable, and `RepoPrompt CE
Tests` for tests. The test scheme delegates to conductor because
`RepoPromptMCP` is an executable-only SwiftPM target. Xcode also exposes the
native `RepoPrompt` and `repoprompt-mcp` product schemes.

See [`docs/architecture/xcode-workspace.md`](docs/architecture/xcode-workspace.md)
for generation, validation, cleanup, and workflow boundaries. Release packaging
is unchanged and does not use the generated workspace.

## Features

- **Context engineering**: Build dense, reviewable prompts with the files and
  repository details an AI model actually needs.
- **Codebase orientation**: Combine file trees, selected file contents, line
  slices, CodeMaps, and Git diffs.
- **Context Builder**: Let an agent explore the repository, identify relevant
  files, and curate context within a token budget. Long-running MCP calls expose
  [request-scoped progress](docs/mcp-progress.md) when the client supplies a
  progress token.
- **Agent orchestration**: Run and coordinate CLI-backed coding agents from the
  native macOS app. See [`docs/worktrees.md`](docs/worktrees.md) for app-managed
  worktrees and `.worktreeinclude` local file copying.
- **MCP server and CLI integration**: Connect external MCP-compatible tools and
  CLI agents to RepoPrompt CE's repository context and agent harness.
- **Multi-root workspaces**: Work across related repositories, packages, and
  documentation folders in one workspace.
- **Reviewable handoffs**: Inspect and refine selected context before sending it
  to another model or agent.

## About the Community Edition

RepoPrompt CE is the free, open-source community edition of RepoPrompt. It is a
native macOS workspace for context engineering, agent orchestration, and local
development.

Maintainers track release signing, Sparkle metadata, dependency pins, and
third-party notices in
[`docs/open-source-readiness.md`](docs/open-source-readiness.md).

## Contributor Documentation

- [`AGENTS.md`](AGENTS.md): coordinated builds, tests, launches, live MCP
  checks, source placement, and contribution preflight
- [`CONTRIBUTING.md`](CONTRIBUTING.md): contribution policy and pull request
  steps
- [`docs/architecture/source-layout.md`](docs/architecture/source-layout.md):
  source ownership and placement rules
- [`docs/architecture/provider-plugins.md`](docs/architecture/provider-plugins.md):
  Agent Mode provider architecture
- [`docs/architecture/xcode-workspace.md`](docs/architecture/xcode-workspace.md):
  generated Xcode developer workflow and boundaries
- [`docs/releasing.md`](docs/releasing.md): release-candidate and publishing
  workflows
- [`docs/open-source-readiness.md`](docs/open-source-readiness.md): public
  readiness inventory

</details>

## License

RepoPrompt CE is licensed under [Apache-2.0](LICENSE).
