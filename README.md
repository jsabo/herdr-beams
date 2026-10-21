# herdr-beams

[![tests](https://img.shields.io/github/actions/workflow/status/jsabo/herdr-beams/tests.yml?branch=main&label=tests)](https://github.com/jsabo/herdr-beams/actions/workflows/tests.yml)
[![herdr 0.9.1+](https://img.shields.io/badge/herdr-0.9.1%2B-8b5cf6)](https://herdr.dev)
[![license Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

**Your agents. Your infrastructure. Teleport Beams in herdr.**

Bring your agent harness to [Teleport Beams](https://beams.run) from the
[herdr](https://herdr.dev) sidebar. Beams provides trusted runtimes with
delegated identity and infrastructure access without secrets. This plugin adds
workspace creation, per-launch agent profiles, and agent status alongside your
local work.

Beams can run the agent harness you choose, including Claude Code, Codex, and Pi.
Claude Code and Codex come preinstalled in the current Beam image; install other
harnesses, such as Pi, inside the Beam and configure them for your tenant's
inference endpoints.

The plugin's profile picker and direct launch actions currently support Claude
Code and Codex. You can run other installed agents from a shell in the Beam;
profile-based launch support depends on the plugin and herdr integrations.

Create a runtime, choose your agent and model, send a task, and follow its progress
without leaving herdr.

[Install](#install) · [Quick start](#quick-start) · [Actions](#actions) ·
[Configuration](#configuration) · [Troubleshooting](docs/troubleshooting.md) ·
[Changelog](CHANGELOG.md)

## Why Beams + herdr?

- **Your infrastructure, your identity.** Beams connects agents to infrastructure
  through delegated Teleport identity, with access governed by Teleport roles and
  attributed in its audit log.
- **Your choice of agent and model.** Install the harness that suits your task,
  including Pi. Claude Code and Codex are preinstalled and have built-in launch
  profiles in this plugin. Inference compatibility and available models depend on
  the harness and your tenant's proxy configuration.
- **Every agent in one sidebar.** herdr shows agent activity and completion across
  your laptop and Beams; open an agent's pane whenever you need it.
- **Isolated execution.** Beams runs workloads in microVMs, separating agent
  execution from your laptop. Teleport handles runtime identity and connectivity;
  this plugin handles launch and workspace controls.
- **Build, serve, and share.** Keep a development service running with `beamctl`
  and publish port 8080 through Teleport.

Check the expiry shown by `herdr plugin action invoke herdr-beams.status` and save
or push work you want to keep before deleting a runtime.

See [how it works](docs/architecture.md) for identity, runtime, security, and the
supported CLI workflow.

## Requirements

On the machine running the plugin:

- herdr 0.9.1 or newer ([installation](https://herdr.dev)).
- Bash 4+, `jq`, and OpenSSH. On macOS: `brew install bash jq`; the system Bash 3.2
  is too old. Make sure herdr can find the newer `bash` on its PATH.
- `tsh` 18.11+ and access to a Teleport Beams tenant.
- The selected agent CLI available in the Beam image.

Log in and configure SSH once, replacing `<tenant>` with your tenant:

```sh
TELEPORT_CLUSTER= tsh login --proxy=<tenant>.beams.sh
tsh --proxy=<tenant>.beams.sh config > ~/.ssh/teleport-beams.config
```

Add this line to `~/.ssh/config` if it is not already present:

```sshconfig
Include ~/.ssh/teleport-beams.config
```

## Install

```sh
herdr plugin install jsabo/herdr-beams
```

Create the plugin's `env` file, or edit it if you already have settings:

```sh
beams_config_dir="$(herdr plugin config-dir herdr-beams)"
mkdir -p "$beams_config_dir"
${EDITOR:-vi} "$beams_config_dir/env"
```

```sh
BEAMS_PROXY=<tenant>.beams.sh
```

Re-run the install command to update. To pin a release, use
`herdr plugin install jsabo/herdr-beams --ref <release-tag>` with a tag from
[Releases](https://github.com/jsabo/herdr-beams/releases).

### Updating a locally linked plugin

A plugin linked with `herdr plugin link` runs directly from its checkout. To keep
that link, update the checkout on the branch you intend to use (usually `main`):

```sh
cd /path/to/herdr-beams
git switch main
git pull --ff-only
```

To switch from a local link to a GitHub installation:

```sh
herdr plugin uninstall herdr-beams
herdr plugin install jsabo/herdr-beams
```

Keep the plugin's configuration directory to retain your settings. If installation
says the plugin is already linked from a local path, use one of these two update
paths.

## Quick start

1. **Create a Beam:** `herdr plugin action invoke herdr-beams.new`. The popup
   installs herdr on the Beam and adds `beam/<id>` to the sidebar.
2. **Launch an agent:** `herdr plugin action invoke herdr-beams.profiles`. Choose
   a profile, Beam, workspace label, and first prompt. Match profile model IDs to
   your tenant's aliases first; see [Agent profiles](#agent-profiles).
3. **Follow the work:** watch the sidebar, then open the agent's pane to read its
   output or answer approval prompts.
4. **Clean up:** `herdr plugin action invoke herdr-beams.rm`. Save your work first;
   deleting a Beam removes its agents and files. Failed deletions retain the
   sidebar entry so you can inspect and retry.

For the default Claude launch, use `herdr plugin action invoke herdr-beams.agent`.
When no Beams exist, this action offers to create one and continues into launch.

**Confirmation behavior:** actions invoked through keybindings or `action invoke`
create and delete without a y/N question. Opening a pane from the plugin menu asks
first. Set `BEAMS_YES=0` in `env` to restore confirmations for interactive actions.
Workspace and prompt questions still appear. Noninteractive scripts do not ask.

## Actions

Run any action with `herdr plugin action invoke herdr-beams.<action>`.

| Action | What it does |
| --- | --- |
| `new` | Create a Beam, install herdr, and offer to launch an agent. |
| `agent` | Launch the default agent in a new unfocused workspace; create a Beam if needed. |
| `profiles` | Pick a harness, model, effort, and approval profile before launch. |
| `claude` / `codex` | Launch the configured harness profile directly. |
| `status` | Show sidebar registration, region, expiry, and SSH address. |
| `services` | List `beamctl` services and optionally follow a service's logs. |
| `publish` | Publish port 8080 through Teleport over HTTPS or TCP. |
| `rm` | Delete one Beam, then remove its sidebar entry after successful deletion. |
| `rm-all` | Delete Beams in order, saving progress; stop on failure and retain entries for undeleted Beams. |
| `demo` | Run the guided build-and-publish walkthrough. |

Expired Beam entries are removed from the sidebar when a popup opens. Failures stay
visible until a key is pressed. The sidebar shows reachability and agent state;
launch popups finish without waiting for the agent.

## Keybindings

Add bindings to `~/.config/herdr/config.toml`, then run `herdr server reload-config`:

```toml
[[keys.command]]
key = "prefix+shift+b"
type = "plugin_action"
command = "herdr-beams.new"
description = "new Beam"

[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "herdr-beams.profiles"
description = "launch an agent in a Beam"

[[keys.command]]
key = "prefix+s"
type = "plugin_action"
command = "herdr-beams.status"
description = "Beam status"

[[keys.command]]
key = "prefix+d"
type = "plugin_action"
command = "herdr-beams.rm"
description = "remove a Beam"
```

`prefix` defaults to `ctrl+b`: press and release it, then press the next key.
Use `herdr-beams.claude` or `herdr-beams.codex` for direct launch bindings.

**Select Local in the sidebar before using a plugin keybinding.** herdr sends the
binding to the selected machine's server; Beams do not have the local plugin.
Running `herdr plugin action invoke ...` from a local shell reaches the local server.

## Configuration

`$(herdr plugin config-dir herdr-beams)/env` is sourced by every script:

| Variable | Default | Meaning |
|---|---|---|
| `BEAMS_PROXY` | required | your tenant, `<name>.beams.sh` |
| `BEAM_LOGIN` | `beams` | SSH login on the Beam |
| `BEAM_AGENT_KIND` | `claude` | herdr agent kind started by `agent` and whose integration `new` installs; the Beam image ships `claude` and `codex`, any other kind needs its CLI installed on the Beam first |
| `BEAM_AGENT_ARGS` | `--dangerously-skip-permissions` | arguments passed to the agent binary; quote more than one, for example `BEAM_AGENT_ARGS="--dangerously-skip-permissions --model opus"` to override the model the Beam image pins |
| `BEAMS_YES` | unset | the actions set it to `1` so a keybinding deletes or creates without a y/N question; `BEAMS_YES=0` here overrides that and every popup asks again |

Settings are read whenever a popup opens; no reload is needed. Use
`BEAM_LABEL_PREFIX` (default `beam/`) to customize sidebar labels. Launches resolve
existing profiles by the Beam UUID, so manual renames and prefix changes do not
prevent an agent from starting.

### Agent profiles

Profiles currently accept `claude` and `codex` harnesses. Installing another agent
in a Beam does not add it to the profile picker; run it from the Beam's shell.

Choose a profile interactively:

```sh
herdr plugin action invoke herdr-beams.profiles
```

| Bundled profile | Harness | Example model | Effort | Approval | Sandbox |
| --- | --- | --- | --- | --- | --- |
| `claude-opus` | Claude Code | `claude-opus-5` | high | bypass | harness default |
| `claude-sonnet` | Claude Code | `claude-sonnet-5` | medium | bypass | harness default |
| `codex-sol` | Codex | `gpt-5.6-sol` | high | never | workspace-write |
| `codex-terra` | Codex | `gpt-5.6-terra` | medium | on-request | workspace-write |

These model IDs are examples. Replace them with aliases supported by your tenant's
inference proxy and installed harness. Add or replace profiles in `profiles.json`
in the same configuration directory as `env`:

```json
{
  "review": {
    "harness": "codex",
    "model": "your-proxy-codex-alias",
    "effort": "high",
    "approval": "on-request",
    "sandbox": "read-only"
  }
}
```

Set defaults in `env`:

```sh
BEAM_AGENT_PROFILE=review
BEAM_CLAUDE_PROFILE=claude-sonnet
BEAM_CODEX_PROFILE=codex-sol
```

Explicit selections override the default profile. With no profile, `agent` keeps
its legacy settings: Claude Code with `--dangerously-skip-permissions` by default.
Set `BEAM_AGENT_ARGS=""` to keep its permission prompts. Profile launches use their
own approval settings; Codex `never` retains the selected sandbox.

See the [profile reference](docs/profiles.md) for overrides, supported values,
validation, and command-line examples.

## Scripting and demos

From a checkout, launch an agent without interactive questions:

```sh
bash bin/beam-agent.sh --profile review <beam-id> review "Review the API" </dev/null
```

Drive a running agent with herdr:

```sh
herdr --machine beam/<id> agent list
herdr --machine beam/<id> agent prompt codex "Read SPEC.md and start." --wait --timeout 600000
```

Use the actual sidebar label if you renamed it. A coding-agent skill is available:
`npx skills add jsabo/herdr-beams --skill herdr-beams -g`.

For a guided demo, run `herdr plugin action invoke herdr-beams.demo`. See the
[demo guide](demo/README.md) for the app-building story, custom tasks, and options.
Recorded timings and versions are in [measurements](docs/measured.md).

## Limitations and security

- This plugin uses `tsh beams`; it does not expose Phaser creation, rotation,
  snapshots, or access-request review. See [compatibility](docs/architecture.md#runtime-lifecycle-and-compatibility).
- Check runtime expiry in `status`. Save work before deleting a Beam. Publishing
  supports port 8080 and one app per Beam in the tested workflow.
- Separate agent workspaces share files. The plugin does not create Git worktrees
  or coordinate concurrent edits; use distinct directories or agree on ownership.
- Concurrent launches of the same harness can race for an agent name.
- Approval prompts may need attention in the agent pane. The plugin installs
  harness integrations, not agent binaries.
- In the tested beta, delegated identities cannot reissue certificates. Use plain
  database clients over VNet for supported engines; `tsh db connect` and
  `tsh kube login` fail in that environment. See [architecture](docs/architecture.md).
- The plugin runs as your local user and installs herdr remotely when needed.
  Review [SECURITY.md](SECURITY.md) and the scripts before installing.

## Troubleshooting

- **Keybinding does nothing:** select Local, check the plugin action ID, and reload
  herdr's config. Try the equivalent `herdr plugin action invoke` command.
- **Cannot list Beams:** check `BEAMS_PROXY` and log in with
  `TELEPORT_CLUSTER= tsh login --proxy=<tenant>.beams.sh`.
- **Beam exists without a sidebar entry:** the popup gives its ID and removal
  command. Fix the reported cause; if herdr is installed, run
  `bash bin/beam-reconcile.sh` from the checkout to register it, or remove the Beam.
- **Cannot copy popup text:** hold Shift while dragging to use terminal selection.

More errors and recovery steps: [Troubleshooting guide](docs/troubleshooting.md).

## Uninstall

Delete any Beams you no longer need before uninstalling:

```sh
herdr plugin action invoke herdr-beams.rm-all
herdr plugin uninstall herdr-beams
```

Check the expiry of any remaining Beams with `tsh beams ls`. Remove leftover
sidebar entries with
`herdr machine remove <profile-id>`. To delete saved settings, get their path with
`herdr plugin config-dir herdr-beams` and remove that directory.

## Development

```sh
brew install bats-core shellcheck jq
tests/run.sh
HERDR_BEAMS_INTEGRATION=1 tests/run.sh   # creates and deletes one real Beam
```

See [Contributing](CONTRIBUTING.md) for local linking and testing, and
[AGENTS.md](AGENTS.md) for repository conventions.

## License

[Apache-2.0](LICENSE), the same as herdr.
