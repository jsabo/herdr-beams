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
- Outbound access from the Beam to GitHub, and `git` in the Beam image, because
  each Beam installs this plugin itself so the keybindings work while it is the
  selected machine. `herdr plugin install` checks the repository out with `git`.

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
   installs herdr and this plugin on the Beam, so the keybindings work while the
   Beam is selected, and adds `beam/<id>` to the sidebar.
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
| `keys` | Install the plugin and its key block on an existing Beam, so the keys work while that Beam is selected. `new` does this for Beams it creates. |
| `demo` | Run the guided build-and-publish walkthrough. |

`agent`, `profiles`, `claude`, `codex`, `status`, `services` and `publish` also run
on a Beam, where they act on that Beam; see
[Keybindings while a Beam is selected](#keybindings-while-a-beam-is-selected).
`new`, `rm`, `rm-all`, `keys` and `demo` are laptop-only and say so if invoked on a
Beam.

Expired Beam entries are removed from the sidebar when a popup opens. Failures stay
visible until a key is pressed. The sidebar shows reachability and agent state;
launch popups finish without waiting for the agent.

## Keybindings

**One rule: the prefix, then Shift and the first letter of the thing.** `prefix`
defaults to `ctrl+b`, which you press and release before the next key.

| Key | Action | Letter |
| --- | --- | --- |
| `ctrl+b` `Shift+B` | new Beam | **B**eam |
| `ctrl+b` `Shift+C` | Claude in a Beam | **C**laude |
| `ctrl+b` `Shift+O` | Codex in a Beam | **O**penAI |
| `ctrl+b` `Shift+A` | pick an agent profile | **A**gent |
| `ctrl+b` `Shift+S` | status | **S**tatus |
| `ctrl+b` `Shift+L` | services and their logs | **L**ogs |
| `ctrl+b` `Shift+E` | publish port 8080 | **E**xpose |
| `ctrl+b` `Shift+K` | delete one Beam | **K**ill |
| `ctrl+b` `Shift+Q` | delete every Beam | **Q**uit the lot |

`demo` and `keys` get no key: one is a walkthrough you start deliberately, the other
a one-off repair. Invoke both with `herdr plugin action invoke herdr-beams.<action>`.

Copy the whole block into `~/.config/herdr/config.toml` and run
`herdr server reload-config`. It is the same block each Beam gets, which is
`config/beam-keys.toml` in this repository.

```toml
[[keys.command]]
key = "prefix+shift+b"
type = "plugin_action"
command = "herdr-beams.new"
description = "new Beam (laptop only)"

[[keys.command]]
key = "prefix+shift+c"
type = "plugin_action"
command = "herdr-beams.claude"
description = "launch Claude in this Beam"

[[keys.command]]
key = "prefix+shift+o"
type = "plugin_action"
command = "herdr-beams.codex"
description = "launch Codex in this Beam"

[[keys.command]]
key = "prefix+shift+a"
type = "plugin_action"
command = "herdr-beams.profiles"
description = "choose an agent profile for this Beam"

[[keys.command]]
key = "prefix+shift+s"
type = "plugin_action"
command = "herdr-beams.status"
description = "this Beam's status"

[[keys.command]]
key = "prefix+shift+l"
type = "plugin_action"
command = "herdr-beams.services"
description = "this Beam's services and their logs"

[[keys.command]]
key = "prefix+shift+e"
type = "plugin_action"
command = "herdr-beams.publish"
description = "expose port 8080 of this Beam"

[[keys.command]]
key = "prefix+shift+k"
type = "plugin_action"
command = "herdr-beams.rm"
description = "delete a Beam (laptop only)"

[[keys.command]]
key = "prefix+shift+q"
type = "plugin_action"
command = "herdr-beams.rm-all"
description = "delete every Beam (laptop only)"
```

### Why those letters, if you change them

Keep off herdr's own keys. A custom command claims its key before herdr parses its
defaults, and the colliding default is then dropped with no warning
(`src/config/keybinds.rs:651` and `:1099-1102` in herdr 0.9.x), so the plugin's
binding works and you quietly lose a herdr action instead. `herdr --default-config`
lists the defaults and `ctrl+b` then `?` shows what is live on the selected machine.

Taken already, after the prefix: `?` `s` `q` `o` `w` `g` `c` `p` `n` `e` `v` `x` `z`
`r` `b` `h` `j` `k` `l` `-` `tab` `1`–`9`, and shifted `R` `N` `G` `W` `D` `T` `X`
`P`. Only `a d f i m t u y` are free unshifted, which is why the set is shifted
throughout. `Shift+D` is the obvious key for delete and is herdr's close-workspace,
hence `Shift+K` for kill.

### Keybindings while a Beam is selected

The same nine keys work whichever machine is selected, and what they act on
follows where you are. herdr rebuilds the live keymap from the selected machine's
own server every time you switch machines, so a key pressed while a Beam is
selected can only come from that Beam's herdr; the plugin is therefore installed on
each Beam as well, with the same block, and `new` does that while creating it.

| Pressed while Local is selected | Pressed while a Beam is selected |
| --- | --- |
| `Shift+C`, `Shift+O`, `Shift+A` ask which Beam to launch in | They launch in the Beam you are looking at |
| `Shift+S` lists the fleet; `Shift+L` and `Shift+E` ask which Beam | They report, list and publish that one Beam |
| `Shift+B`, `Shift+K`, `Shift+Q` create and delete Beams | They say they belong on the laptop and change nothing |

Creating and deleting Beams stays on the laptop, because it needs your own
Teleport login and only the laptop's herdr owns the machines rail. `ctrl+b` then
`g` opens the machine list: pick Local, then press the key again.

For a Beam created before plugin 0.9.0, run
`herdr plugin action invoke herdr-beams.keys` once. Running
`herdr plugin action invoke ...` in a shell always reaches that host's own server.

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
| `env` | The same configuration directory **on each Beam** | The plugin, when it sets the Beam up | Nothing; it is rewritten from your laptop's settings, plus `BEAM_SELF_ID` and `BEAM_SELF_UUID` |
| `config.toml` | `~/.config/herdr` **on each Beam** | The plugin appends one block to it | Nothing; the block starts at `# herdr-beams-keys`, and removing it takes the keys off that Beam |

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
values containing spaces. Edit the copy on your laptop; the copy the plugin writes
on each Beam is derived from it and is rewritten on the next setup.

### Choose a bundled profile

Open the picker with `ctrl+b` `Shift+A` if you installed
[the recommended keys](#keybindings), or run this from your local shell. With Local
selected the picker asks which Beam to launch in; with a Beam selected it launches
in that Beam:

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
| `BEAM_PLUGIN_SOURCE` | `jsabo/herdr-beams` | The repository a Beam installs this plugin from, so its keybindings work; point it at a fork to try one on a Beam |
| `BEAM_SELF_ID`, `BEAM_SELF_UUID` | Unset | Written by the plugin into a Beam's own `env`, never on the laptop; they are how a script knows it is running in that Beam |
| `BEAM_AGENT_KIND` | `claude` | Legacy harness when no profile is selected |
| `BEAM_AGENT_ARGS` | `--dangerously-skip-permissions` | Legacy whitespace-separated arguments when no profile is selected |

For new setups, select `BEAM_AGENT_PROFILE` instead of using legacy arguments.
An unprofiled launch still defaults to Claude permission bypass; set
`BEAM_AGENT_ARGS=""` to retain prompts if deliberately using that legacy mode.
Plugin create/delete confirmations are separate from agent permission prompts.

Codex launches use a process-scoped detection hint and register trust for the
installed Herdr `SessionStart` hook. Other hooks keep their own trust settings.
See [troubleshooting](docs/troubleshooting.md) if Codex setup or detection fails.

The hint also clears the pane, so a Codex pane and a Claude pane read the same:
Codex draws inline and would otherwise leave the shell prompt and the whole launch
command above its header, where Claude Code clears the screen itself.

Every launch also reports the harness's own name — `Claude Code`, `OpenAI Codex`,
or the agent kind for anything else — as a pane token called `harness`. Add a row
to your sidebar to show it, which gives a Codex row the third line a Claude row
gets from its live terminal title:

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", "workspace", "agent"],
  ["state_text"],
  [{ token = "$harness", dim = true }],
]
```

The `$` is herdr's marker for a token a plugin reported rather than one of its own;
the reported name carries no `$`. The row disappears for an agent that reports
nothing, so it is safe for agents you start by hand.

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
- The plugin runs as your local user and installs herdr remotely when needed. It
  also installs itself on each Beam and appends one block to that Beam's
  `~/.config/herdr/config.toml`, which is what makes the keybindings work while
  the Beam is selected. Nothing runs in the other direction: a Beam cannot create
  or delete Beams, and cannot change your laptop's sidebar.
  Review [SECURITY.md](SECURITY.md) and the scripts before installing.

## Troubleshooting

- **Keybinding does nothing:** press `ctrl+b` then `?` to see what herdr has live
  for the selected machine. With Local selected, check the action ID and reload the
  config. With a Beam selected, the keys come from that Beam: run
  `herdr plugin action invoke herdr-beams.keys` for a Beam created before 0.9.0,
  and remember that `Shift+B`, `Shift+K` and `Shift+Q` are laptop-only. A key that
  is also a herdr default does reach the plugin, and takes that herdr action away
  instead, so check `herdr --default-config` if a herdr key stopped working.
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

The copy of the plugin on a Beam goes away with the Beam, within 24 hours. To take
it off a Beam you are keeping, disable it there and delete the key block:

```sh
herdr --machine beam/<id> plugin disable herdr-beams
ssh beams@<uuid>.<tenant>.beams.sh "sed -i '/^# herdr-beams-keys\$/,\$d' ~/.config/herdr/config.toml"
herdr --machine beam/<id> server reload-config
```

The plugin appends its block at the end, so that `sed` deletes from the
`# herdr-beams-keys` marker to the end of the file. Move anything you added after
the block first. `--machine` forwards only API-backed commands, which is why this
disables the plugin rather than uninstalling it.

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
