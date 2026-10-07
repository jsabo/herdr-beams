# herdr-beams

[![tests](https://img.shields.io/github/actions/workflow/status/jsabo/herdr-beams/tests.yml?branch=main&label=tests)](https://github.com/jsabo/herdr-beams/actions/workflows/tests.yml)
[![herdr 0.9.1+](https://img.shields.io/badge/herdr-0.9.1%2B-8b5cf6)](https://herdr.dev)
[![license Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

**Your coding agents in a trusted runtime that holds your identity, one keypress away.**

A [herdr](https://herdr.dev) plugin for [Teleport Beams](https://beams.run).
A Beam is an ephemeral, isolated runtime for an agent: a microVM (a small, fast virtual
machine) that Teleport provisions with your identity delegated into it and connects to
your infrastructure and inference endpoints. You press a key in herdr, the terminal
workspace manager for coding agents, and the Beam appears in your sidebar as a machine.
Press another and Claude Code is working in it as you, with no password typed and no
key copied. No API key exists on your laptop or in the Beam. When the work is done the
Beam expires on its own: nothing to patch, nothing to clean up, and nothing left
running that still holds your identity.

<!-- ![The New Beam popup finishing: four ticked phases and the Beam's card, with the new machine in herdr's sidebar](assets/new-beam.png) -->

## Requirements

- herdr 0.9.1 or newer on the laptop (`brew install herdr`)
- bash 4 or newer on the laptop (macOS ships 3.2; `brew install bash` puts a current one
  where herdr finds it)
- `tsh` 18.11 or newer, logged in to your Beams tenant:
  `TELEPORT_CLUSTER= tsh login --proxy=<tenant>.beams.sh`
- `jq`, the command-line JSON (JavaScript Object Notation) processor
- The `tsh config` block for the tenant in your SSH (Secure Shell) config, so OpenSSH
  can reach a Beam:

  ```sh
  tsh --proxy=<tenant>.beams.sh config > ~/.ssh/teleport-beams.config
  printf 'Include ~/.ssh/teleport-beams.config\n' >> ~/.ssh/config
  ```

## Install

```sh
herdr plugin install jsabo/herdr-beams
printf 'BEAMS_PROXY=<tenant>.beams.sh\n' > "$(herdr plugin config-dir herdr-beams)/env"
herdr plugin action invoke herdr-beams.new
```

The last line opens the New Beam popup. Eighteen seconds later the Beam is in your
sidebar. To update, run the install command again.

Keybindings are yours to choose. In `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+shift+b"
type = "plugin_action"
command = "herdr-beams.new"      # <plugin id>.<action id>, not the plugin's name
description = "new Beam"

[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "herdr-beams.agent"
description = "start an agent in a Beam"

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

[[keys.command]]
key = "prefix+shift+q"
type = "plugin_action"
command = "herdr-beams.rm-all"
description = "remove every Beam"
```

Then `herdr server reload-config`. `prefix` is herdr's prefix key, `ctrl+b` by
default: press it, release, then press the letter. With these, `prefix+a` is the
whole way in (with no Beam it creates one, then starts Claude Code in it) and
`prefix+shift+q` is the whole way out: every Beam deleted, every sidebar entry gone,
and with them the agents, which run on the Beams. Then `prefix+q` detaches from herdr.

Press the chords with Local selected in the sidebar. herdr runs a plugin action on the
selected machine's herdr server, and the one on a Beam has no plugins, so with a Beam
selected the chord does nothing. `herdr plugin action invoke herdr-beams.<id>` from a
shell always goes to the local server.

A popup opened by a keybinding, or by `herdr plugin action invoke`, does not ask
"are you sure": pressing the chord was the decision. The same popup opened from
herdr's plugin menu asks first. Questions that need an answer from you (the workspace
label, the first prompt) are asked either way, and Enter takes the default. To get
the questions back on keybindings too, add `BEAMS_YES=0` to the settings file (see
[Settings](#settings)); delete the line to turn them off again. Each popup reads the
file when it opens, so there is nothing to reload.

The letters stay clear of herdr's own chords: `prefix+b` toggles the sidebar, so a new
Beam is `prefix+shift+b`, and `prefix+shift+d` closes the workspace, so remove-all
sits next to detach as `prefix+shift+q`. Prefix chords are what the other public
herdr plugins use, and nothing outside herdr can take one, because the terminal and
the window manager only ever see the prefix. If you prefer one-keystroke bindings,
herdr's [keyboard guide](https://herdr.dev/docs/keyboard) recommends the `ctrl+alt`
family for direct chords and lists the ones desktops already own.

## What you get

Every entry is a popup, so you can read what it did, and every entry has an action of
the same id, so `herdr plugin action invoke herdr-beams.<id>` opens it from any shell.

| Entry | What it does |
|---|---|
| `new` | Creates a Beam, installs herdr on it, adds it to the sidebar with the Beam's id as the label, and offers to start an agent. Prints a tick and a timestamp per phase. |
| `agent` | Picks a Beam (or creates one when there is none), opens a workspace on it, starts Claude Code in the workspace's root pane and sends a first prompt. The agent list in the sidebar shows it working, then done. |
| `status` | One card per Beam: whether it is in the sidebar, region, expiry, SSH address. Whether herdr can reach it is the dot on its sidebar entry. |
| `services` | `beamctl list` on a Beam, then follow one service's logs. |
| `publish` | Exposes port 8080 of a Beam as a Teleport application and prints its URL (web address). |
| `rm` | Deletes a Beam and its sidebar entry. Asks first from the menu, not from a keybinding. |
| `rm-all` | Lists every Beam on the tenant, then deletes them all with their sidebar entries. Asks once from the menu, not from a keybinding. |
| `demo` | The scripted walkthrough, with a pause before each step (see [Demo](#demo)). |

Every popup first drops sidebar entries whose Beam has expired. A popup that fails
stays open with the reason until you press a key. No popup waits on an agent or
re-checks what the sidebar already shows: the agent list is where an agent's state
lives, and the dot on a machine entry is whether herdr can reach it.

A popup closes when its script ends: any key at `press any key to close` or at a y/N
question, Enter at a question that wants a value (it takes the default), and Ctrl+C
anywhere, which closes it at once. The one time Ctrl+C leaves the popup open is when
`new` has already created the Beam: the popup then says the Beam exists without a
sidebar entry and waits for a key, so you know to remove it or run `new` again. To
copy a command out of a popup, hold Shift while you drag over it, then copy as usual:
herdr owns the mouse, and Shift hands the drag back to the terminal.

<!-- ![The Beam status popup: one card per Beam with its sidebar entry, region, expiry and SSH address](assets/status.png) -->

## How it works

Each point is a mechanism you can check, not a claim. The Beams behaviour is in the
[Teleport Beams](https://beams.run) pages; the timings are in
[docs/measured.md](docs/measured.md).

- **The agent acts as you, without your credentials.** A Beam carries a delegated
  identity: a certificate issued for the Beam on your behalf, with a subset of your
  roles. `tsh` inside the Beam is already logged in, and every SSH or database action
  it takes is attributed in the audit log to you and to the Beam's own workload
  identity. The private key never leaves Teleport, and the Beam cannot use the identity
  to mint new certificates for anything else.
- **No API keys exist.** The Beam's environment points `ANTHROPIC_BASE_URL` and
  `OPENAI_BASE_URL` at inference endpoints the tenant proxies; the "key" is a
  placeholder string. Nothing to rotate, nothing to leak, usage attributed per user.
  Your inference, your harness.
- **Services outlive sessions.** `beam-init` is the Beam's init process and `beamctl`
  its service manager. A dev server started with `beamctl start` keeps running after
  every shell closes, and an agent can start one itself.
- **Publish without a load balancer.** `tsh beams publish` turns port 8080 into a
  Teleport application served over HTTPS (Hypertext Transfer Protocol Secure): an
  address only your login can open, with every request in the audit log. Port 8080 is
  the only port the beta publishes.
- **Expiry is the cleanup.** Beams live 24 hours. Nothing accumulates.

herdr adds the part Beams do not have: one sidebar for your laptop and every Beam, an
agent state (`working`, `blocked`, `done`) you can see and get notified about, and
`herdr --machine <beam>`, which forwards any herdr command to the Beam's own herdr
server so a shell, a script or another agent can drive what runs there.

| | Teleport Beams | herdr |
|---|---|---|
| Sandbox, egress, 24 h lifetime | yes | no |
| Identity for `tsh`: SSH nodes, databases over VNet | delegated from your login | no |
| Inference endpoint and keys | proxied by the tenant | no |
| Audit and session recording | yes | no |
| Keep a process alive after SSH drops | `beamctl` (services) | panes owned by a background server |
| Agent state in a sidebar, notifications | no | yes |
| Several machines in one window | no | yes |
| Scriptable control of agents | no | socket API and CLI |

VNet is Teleport's virtual network: inside the Beam a database gets a local hostname,
and a plain `psql` or `mysql` client connects through it with the Beam's identity.

The only overlap is "keep an interactive agent alive and get back to it". Use herdr
for that. Use `beamctl` for processes that are not agents: the dev server behind
`tsh beams publish`, a database, a `claude -p` loop.

Inside a Beam, herdr runs as a plain user process reparented to `beam-init`. It
survives the SSH session that started it, and its panes inherit the Beam's environment,
so the inference endpoints and the Teleport identity variables are present in every
agent without configuration.

## What this plugin runs on your machine

A herdr plugin is ordinary code that runs as your user. This one is a few short bash
scripts in `bin/`, and they do exactly this:

- **Commands it issues**: `tsh --proxy=<BEAMS_PROXY> beams ls|add|rm|publish`,
  `ssh beams@<uuid>.<tenant>` (through your SSH config, one shared connection per
  Beam), `herdr machine add|remove|status|list`, and `herdr --machine <beam> …` for
  workspaces and agents on the Beam.
- **On the Beam, once**: `curl -fsSL https://herdr.dev/install.sh | sh` if herdr is
  missing, `herdr integration install claude`, and a section
  `## Inside a Beam (added by herdr-beams)` appended to the Beam's `~/.claude/CLAUDE.md`
  and `~/AGENTS.md`. The text is `beam_notes` in `bin/common.sh`: the facts an agent
  otherwise spends its first minutes rediscovering (which `tsh` commands the delegated
  identity cannot run, which database engines have a VNet path, which clients are not
  installed).
- **Where it writes on the laptop**: your settings in
  `$(herdr plugin config-dir herdr-beams)/env`, a cache of the Beam list in herdr's
  plugin state directory, and machine entries in herdr's own machine list. Nothing
  else. It stores no credentials; `tsh` holds your login.
- **Agents run with permission prompts off.** `BEAM_AGENT_ARGS` defaults to
  `--dangerously-skip-permissions`, because the Beam is the boundary: the sandbox,
  Teleport's role-based access control (RBAC) and the audit log are the guardrails,
  and there is no one at the keyboard to answer prompts. Set `BEAM_AGENT_ARGS=""` to
  keep the prompts.

Listings on herdr.dev are not reviewed by herdr. Read `bin/` before you install;
it is short.

## Settings

`$(herdr plugin config-dir herdr-beams)/env` is sourced by every script:

| Variable | Default | Meaning |
|---|---|---|
| `BEAMS_PROXY` | required | your tenant, `<name>.beams.sh` |
| `BEAM_LOGIN` | `beams` | SSH login on the Beam |
| `BEAM_AGENT_KIND` | `claude` | herdr agent kind started by `agent` and whose integration `new` installs |
| `BEAM_AGENT_ARGS` | `--dangerously-skip-permissions` | arguments passed to the agent binary; quote more than one, for example `BEAM_AGENT_ARGS="--dangerously-skip-permissions --model opus"` to override the model the Beam image pins |
| `BEAMS_YES` | unset | the actions set it to `1` so a keybinding deletes or creates without a y/N question; `BEAMS_YES=0` here overrides that and every popup asks again |

## Scripting and agents

Everything a popup does is also a plain command. The whole surface is herdr's
`--machine` prefix:

```sh
herdr --machine neon-panel workspace create --cwd '~' --label api --no-focus
herdr --machine neon-panel agent start claude --kind claude --pane w2:p1 -- --dangerously-skip-permissions
herdr --machine neon-panel agent prompt claude "Read SPEC.md and start." --wait --timeout 600000
```

The scripts in `bin/` take their arguments on the command line and never ask a question
when there is no terminal, so an agent on your laptop can call them:
`bash bin/beam-agent.sh <beam> <workspace> "<prompt>" </dev/null`. A skill that
teaches a coding agent this flow is in `skills/herdr-beams/`:
`npx skills add jsabo/herdr-beams --skill herdr-beams -g`.

<!-- ![herdr's sidebar with a Beam machine and its agent marked done](assets/agent-done.png) -->

## Demo

`demo/demo.sh` tells one of two stories, with a pause before each step and a timer
after it: an agent builds an app in a Beam, starts it as a service, and you publish
it (seven steps, about 52 s unattended); or, with `DEMO_PROMPT` set, an agent runs
your task as you (five steps). Run it as a popup so the audience watches the sidebar
change behind it:

```sh
herdr plugin pane open --plugin herdr-beams --entrypoint demo
```

The popup inherits herdr's environment, not your shell's, so demo variables go on the
command line (`--env DEMO_AUTO=1`). The talk tracks, the variables and a pre-flight
checklist are in [demo/README.md](demo/README.md).

## Limitations

- Publishing is port 8080 only and one app per Beam.
- A Beam lives 24 hours. The plugin treats its own list as a cache and reconciles
  against `tsh beams ls` before acting.
- Inside a Beam, VNet gives a path to postgres, mysql, sql-server and cockroachdb.
  Other engines resolve to the public proxy and clients hang; the seeded notes tell the
  agent not to probe them.
- The delegated identity cannot reissue certificates, so `tsh db connect`,
  `tsh proxy` and `tsh kube login` fail inside a Beam by design.
- `tsh beams exec` re-splits its command on the remote side, so pipes and quotes do
  not survive it. The plugin uses `ssh` for anything with a pipe.

## Uninstall

```sh
herdr plugin uninstall herdr-beams
rm -r "$(herdr plugin config-dir herdr-beams)"
```

Run the `rm-all` popup first if you want the Beams gone too. Otherwise they expire on
their own within 24 hours, and `tsh beams rm <id>` removes one sooner. Sidebar entries
for Beams are ordinary herdr machines; remove any left with `herdr machine remove`.

## Troubleshooting

- **The popup closed before you could read it.** A failing popup stays open with the
  reason and `beams: failed (exit N)` until a key is pressed. If you still see nothing,
  the popup never started: look for `plugin.pane.open` in
  `~/.config/herdr/herdr-server.log`.
- **A keybinding does nothing.** A `plugin_action` binding needs the plugin id
  (`herdr-beams.new`), not its name, and `herdr server reload-config` after editing the
  file. A `type = "shell"` binding runs through `/bin/sh -lc`, which reads
  `~/.profile`, not `~/.zshrc`; if `herdr` is not on that PATH, write its full path.
- **A keybinding does nothing while a Beam is selected in the sidebar.** herdr sends
  a plugin action to the selected machine's server, and the herdr on a Beam has no
  plugins (`herdr --machine <id> plugin list` says so). Select Local, then press the
  chord, or run `herdr plugin action invoke herdr-beams.<id>` from a shell.
- **You cannot select text in a popup.** herdr captures the mouse for its own
  selection. Hold Shift while you drag; the terminal then selects natively and Cmd+C
  (or your terminal's copy key) takes it.
- **`cannot list Beams on <tenant>`.** tsh's own error is printed above it. The plugin
  only uses the tenant in `BEAMS_PROXY`; if you are not logged in:
  `TELEPORT_CLUSTER= tsh login --proxy=<tenant>.beams.sh` (the empty
  `TELEPORT_CLUSTER` matters when that variable is set in your shell).
- **`no Beam named <id>`.** The id is checked against `tsh beams ls` before anything
  runs. Beams have a short id (`neon-panel`) and a UUID (universally unique
  identifier); the popups take the short id.
- **`Beam <id> exists without a sidebar entry`.** The `new` popup failed after the
  Beam was created (SSH never came up, or the install failed). Remove it with the `rm`
  popup or `bash bin/beam-rm.sh <id>`, or fix the cause and run `new` again; the
  startup hook adds a sidebar entry for any Beam that already has herdr on it.
- **`plugin requires Herdr 0.9.1 or newer`** when linking or installing. The running
  herdr server is older than the binary. `herdr server stop` (this ends its panes),
  then start herdr again.
- **`ssh: … target host <id> is offline or does not exist`.** A Beam's SSH hostname
  is its UUID, not its short id. The plugin always uses the UUID; if you connect by
  hand, take it from `tsh beams ls -f json`.
- **`machine add` fails without a terminal.** herdr is not on the Beam yet. The `new`
  popup installs it; for a Beam created elsewhere, run
  `ssh beams@<uuid>.<tenant> 'curl -fsSL https://herdr.dev/install.sh | sh'` first.
- **`herdr: server shut down: server is shutting down`** when launching herdr. The
  client attached while an earlier server was still stopping. Run `herdr` again.
- **An `Action interrupted` toast** in the top right is herdr's own message for a
  server call that was cancelled, usually by Esc or a closed popup. The Beam and its
  agents are unaffected.
- **A direct chord does nothing, or resizes the window.** Most macOS terminals
  compose plain `alt` chords into a character before herdr sees them, and window
  managers such as Magnet take some `ctrl+alt` chords system-wide. The `prefix+`
  bindings above avoid both: only herdr sees the key after the prefix.

## Development

```sh
brew install bats-core shellcheck
tests/run.sh                              # lint + unit tests, offline, a few seconds
HERDR_BEAMS_INTEGRATION=1 tests/run.sh    # also creates and deletes one real Beam
herdr plugin link "$(pwd)"
herdr plugin action invoke herdr-beams.status
herdr plugin log list --plugin herdr-beams
```

The unit tests run every script, and the demo, against fake `tsh`, `herdr` and `ssh`
commands and assert on the exact command lines issued, including every question a
popup can ask. Conventions are in [AGENTS.md](AGENTS.md), how to contribute in
[CONTRIBUTING.md](CONTRIBUTING.md), what the plugin touches in
[SECURITY.md](SECURITY.md).

## License

Apache-2.0, the same as herdr.
