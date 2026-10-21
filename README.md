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
  is too old. If launched with an older Bash, the plugin automatically switches to
  Bash 4+ from PATH or the standard Apple Silicon / Intel Homebrew locations.
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
BEAM_AGENT_PROFILE=claude-opus
```

The plugin supplies four profiles. You create `env` yourself; a custom
`profiles.json` is optional. See [Configuration](#configuration) for file locations,
profile defaults, overrides, and Claude/Codex YOLO examples.

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

### Where settings live

Run this on your laptop to find the configuration directory:

```sh
herdr plugin config-dir herdr-beams
```

By default it is `~/.config/herdr/plugins/config/herdr-beams` on macOS and Linux
(unless your XDG configuration location differs). Use the command's output as the
authoritative path.

| File | Location | Who creates it? | What to edit |
| --- | --- | --- | --- |
| `env` | Configuration directory | You, during setup | Tenant and default profile choices |
| `profiles.json` | Configuration directory | You, optionally | Additional profiles or replacements for bundled profiles |
| `profiles/defaults.json` | Installed plugin checkout | Supplied with the plugin | View only; updates replace it |

You do not need a custom `profiles.json` to use the four bundled profiles.
Multiple GitHub installation directories can remain after updates; edit the
configuration directory rather than any installation checkout. Plugin updates
preserve your `env` and custom `profiles.json`.

### Recommended starting configuration

Create or edit `env`:

```sh
beams_config_dir="$(herdr plugin config-dir herdr-beams)"
mkdir -p "$beams_config_dir"
${EDITOR:-vi} "$beams_config_dir/env"
```

For profile-based launches, use this minimal content, replacing the tenant:

```sh
BEAMS_PROXY=<tenant>.beams.sh
BEAM_AGENT_PROFILE=claude-opus
```

If migrating from an older setup, remove `BEAM_AGENT_KIND` and `BEAM_AGENT_ARGS`
from this file when you no longer need legacy launches. In particular, remove old
`--dangerously-skip-permissions` arguments. `BEAM_AGENT_PROFILE` selects the profile
for the generic `agent` action and the agent offered after `new`; dedicated
Claude/Codex actions have their own defaults below.

`env` is a Bash file sourced by the plugin. Use `NAME=value` assignments and quote
values containing spaces. Keep this file on your laptop, not inside a Beam.

### Choose a bundled profile

Select **Local** in herdr, then open the picker with **Prefix → A** if you installed
[the example binding](#keybindings), or run this from your local shell:

```sh
herdr plugin action invoke herdr-beams.profiles
```

| Profile | Model | Effort | Permissions | Agent command networking |
| --- | --- | --- | --- | --- |
| `claude-opus` | `anthropic.claude-opus-5` | high | Normal Claude permission prompts | Controlled by Claude settings |
| `claude-sonnet` | `anthropic.claude-sonnet-5` | medium | Normal Claude permission prompts | Controlled by Claude settings |
| `codex-sol` | `openai.gpt-5.6-sol` | high | On-request approval; workspace-write sandbox | Disabled in the sandbox |
| `codex-terra` | `openai.gpt-5.6-terra` | medium | On-request approval; workspace-write sandbox | Disabled in the sandbox |

Claude's normal permission mode is not network isolation; existing Claude allow
rules still apply. Codex's network setting restricts sandboxed commands, not the
connection used for model inference. Approval modes ask when the harness requires
approval, rather than before every action.

These model IDs must be supported by your tenant's inference proxy. See the
[profile reference](docs/profiles.md) for model verification and all field values.
Profiles support `claude` and `codex`; other installed harnesses can run from a
Beam shell but do not automatically appear in this picker.

### Add custom Claude and Codex YOLO profiles

Create the optional file yourself:

```sh
beams_config_dir="$(herdr plugin config-dir herdr-beams)"
${EDITOR:-vi} "$beams_config_dir/profiles.json"
```

For a new file, paste this complete JSON. If the file already exists, add these
entries inside its existing outer object instead of replacing your other profiles:

```json
{
  "claude-yolo": {
    "harness": "claude",
    "model": "anthropic.claude-opus-5",
    "effort": "high",
    "approval": "bypass"
  },
  "codex-yolo": {
    "harness": "codex",
    "model": "openai.gpt-5.6-sol",
    "effort": "high",
    "approval": "never",
    "sandbox": "danger-full-access"
  }
}
```

Save the file (in Vim: **Esc**, `:wq`, **Enter**). These choices are added to the
picker alongside the bundled profiles; merely creating them does not change your
default launch profile.

`claude-yolo` bypasses Claude permission prompts. `codex-yolo` suppresses approvals
and disables Codex's own file/network sandbox; external Beam and Teleport controls
still apply. Omit `network_access` with `danger-full-access`: that profile field is
only valid with `workspace-write`.

For Codex without prompts but with the workspace sandbox retained, use
`"approval": "never"`, `"sandbox": "workspace-write"`, and
`"network_access": true` instead. `never` alone does not disable the sandbox or
enable network access.

### Override an existing profile

Custom records are combined with the bundled profiles by name:

- A new name, such as `claude-yolo`, adds a choice.
- An existing name, such as `codex-sol`, replaces that entire bundled record.
  Include every required field; individual fields are not merged.
- Remove a custom replacement to restore that profile's bundled settings on the
  next launch. Updates never rewrite your custom replacements.

For example, put this record in `profiles.json` to keep Codex Sol's prompts and
workspace sandbox while allowing its commands to reach Teleport and repositories:

```json
{
  "codex-sol": {
    "harness": "codex",
    "model": "openai.gpt-5.6-sol",
    "effort": "high",
    "approval": "on-request",
    "sandbox": "workspace-write",
    "network_access": true
  }
}
```

### Set the default for each action

Edit `env` to select any bundled or custom profile by its exact name:

| Variable | Default when unset | Used by |
| --- | --- | --- |
| `BEAM_AGENT_PROFILE` | No profile; legacy settings below | Generic `agent` action and the agent offered after `new` |
| `BEAM_CLAUDE_PROFILE` | `claude-opus` | Dedicated `claude` action |
| `BEAM_CODEX_PROFILE` | `codex-sol` | Dedicated `codex` action |

After creating the YOLO profiles above, this optional configuration makes them the
action defaults:

```sh
BEAMS_PROXY=<tenant>.beams.sh
BEAM_AGENT_PROFILE=claude-yolo
BEAM_CLAUDE_PROFILE=claude-yolo
BEAM_CODEX_PROFILE=codex-yolo
```

Leave the recommended defaults in place if you prefer to choose YOLO only from
the picker. A picker choice or explicit `--profile` selects that launch's profile
instead of `BEAM_AGENT_PROFILE`; profile launches do not append `BEAM_AGENT_ARGS`.
Use a Claude profile for `BEAM_CLAUDE_PROFILE` and a Codex profile for
`BEAM_CODEX_PROFILE`.

### Apply and check changes

No reload is needed for `env` or `profiles.json`: each new popup reads them.
Existing agents keep their launch settings; start a new agent to use changes.
Herdr keybinding edits separately require `herdr server reload-config`.

```sh
beams_config_dir="$(herdr plugin config-dir herdr-beams)"
cat "$beams_config_dir/env"
# Optional: validate your custom file's JSON syntax.
jq empty "$beams_config_dir/profiles.json"
herdr plugin action invoke herdr-beams.profiles
```

The picker also validates profile fields. Keep one JSON object with no comments or
trailing commas. The [profile reference](docs/profiles.md) lists supported values.

### Other settings and legacy launches

| Variable | Default | Meaning |
| --- | --- | --- |
| `BEAMS_PROXY` | Required | Tenant, `<tenant>.beams.sh` |
| `BEAM_LOGIN` | `beams` | SSH login on the Beam |
| `BEAM_LABEL_PREFIX` | `beam/` | Sidebar label prefix; existing registrations are resolved by UUID |
| `BEAMS_YES` | Unset | Keybinding actions set `1` to skip their create/delete confirmations; set `0` in `env` to retain those confirmations |
| `BEAM_AGENT_KIND` | `claude` | Legacy harness when no profile is selected |
| `BEAM_AGENT_ARGS` | `--dangerously-skip-permissions` | Legacy whitespace-separated arguments when no profile is selected |

For new setups, select `BEAM_AGENT_PROFILE` instead of using legacy arguments.
An unprofiled launch still defaults to Claude permission bypass; set
`BEAM_AGENT_ARGS=""` to retain prompts if deliberately using that legacy mode.
Plugin create/delete confirmations are separate from agent permission prompts.

Codex launches use a process-scoped detection hint and register trust for the
installed Herdr `SessionStart` hook. Other hooks keep their own trust settings.
See [troubleshooting](docs/troubleshooting.md) if Codex setup or detection fails.

## Scripting and demos

From a checkout, launch an agent without interactive questions:

```sh
bash bin/beam-agent.sh --profile codex-sol <beam-id> review "Review the API" </dev/null
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
