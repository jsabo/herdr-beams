# How herdr-beams works

[Back to the README](../README.md)

[Teleport Beams](https://beams.run) provides the runtime, infrastructure
connectivity, and delegated identity. This plugin adds herdr launch actions,
workspaces, and agent controls. Measurements from the tested beta, with dates and
versions, are recorded in [measurements](measured.md).

- **Infrastructure access through delegated identity.** Beams gives the runtime
  a Teleport-issued identity linked to its delegator. Teleport attributes activity
  to the user and the runtime's workload identity. In the tested beta, delegation
  inherited the user's role set. The current product site describes scoped roles
  and reviewed execution plans; this plugin does not configure that review flow.
- **Inference credentials stay outside the Beam.** The runtime's
  `ANTHROPIC_BASE_URL` and `OPENAI_BASE_URL` point at tenant-proxied endpoints.
  Teleport injects upstream credentials through its proxy, so inference API keys
  are not stored in the Beam. Model availability depends on the tenant and harness.
- **Services outlive sessions.** `beam-init` is the Beam's init process and `beamctl`
  its service manager. A dev server started with `beamctl start` keeps running after
  every shell closes, and an agent can start one itself.
- **Publish without a load balancer.** `tsh beams publish` turns port 8080 into a
  Teleport application served over HTTPS: an
  address only your login can open, with every request in the audit log. Port 8080 is
  the only port the beta publishes.
- **Check the runtime expiry.** The status action displays the expiry returned by
  `tsh beams ls`. Save work before deletion or expiry; see the lifecycle notes below.

herdr adds the part Beams do not have: one sidebar for your laptop and every Beam, an
agent state (`working`, `blocked`, `done`) you can see and get notified about, and
`herdr --machine beam/<id>`, which forwards any herdr command to the Beam's own herdr
server so a shell, a script or another agent can drive what runs there. Beams is the
runtime you can trust with your identity; herdr is the place you can see and drive
every agent. Neither does the other's job.

| | Teleport Beams | herdr |
|---|---|---|
| Runtime isolation and lifecycle | provided by Beams | no |
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

## Runtime lifecycle and compatibility

The plugin implements the `tsh beams` workflow exercised in the tested beta. It
uses the expiry supplied by the CLI rather than setting a fixed lifetime.

The [Beams CLI documentation](https://goteleport.com/docs/beams/) describes a
24-hour beta expiry. The current [product architecture](https://www.beams.run/how-it-works.html)
describes Phasers as persistent agent environments, with underlying Beams rotating
every 12 hours and retaining `/home` state. These describe different lifecycle
models; VM rotation does not imply deletion of a Phaser's retained data.

This plugin does not issue `tsh phasers` commands or manage Phaser rotation,
snapshots, forks, or execution-plan approvals. Confirm CLI and tenant compatibility
before applying the newer product workflows. Check expiry with the plugin's
`status` action or `tsh beams ls`, and save or push work before deletion or expiry.

## What this plugin runs on your machine

A herdr plugin is ordinary code that runs as your user. This one is a few short bash
scripts in `bin/`, and they do exactly this:

- **Commands it issues**: `tsh --proxy=<BEAMS_PROXY> beams ls|add|rm|publish`,
  `ssh beams@<uuid>.<tenant>` (through your SSH config, one shared connection per
  Beam), `herdr machine add|rename|remove|list`, and `herdr --machine beam/<id> …` for
  workspaces and agents on the Beam.
- **On the Beam**: `curl -fsSL https://herdr.dev/install.sh | sh` if herdr is
  missing, `herdr integration install <selected harness>`, and a section
  `## Inside a Beam (added by herdr-beams)` appended to the Beam's `~/.claude/CLAUDE.md`
  and `~/AGENTS.md`. The text is `beam_notes` in `bin/common.sh`: the facts an agent
  otherwise spends its first minutes rediscovering (which `tsh` commands the delegated
  identity cannot run, which database engines have a VNet path, which clients are not
  installed). Existing-Beam launches install the selected integration idempotently; a launch
  handed directly from creation reuses the integration just installed.
- **Where it writes on the laptop**: your settings in
  `$(herdr plugin config-dir herdr-beams)/env`, a cache of the Beam list in herdr's
  plugin state directory, machine entries in herdr's own machine list, and optional
  profile overrides in the plugin config directory. It stores no credentials;
  `tsh` holds your login.
- **Legacy agents run with permission prompts off.** `BEAM_AGENT_ARGS` defaults to
  `--dangerously-skip-permissions`, because the Beam is the boundary: the sandbox,
  Teleport's role-based access control (RBAC) and the audit log are the guardrails,
  and there is no one at the keyboard to answer prompts. Set `BEAM_AGENT_ARGS=""` to
  keep the prompts. Profiles select approval and sandbox settings per launch.

herdr does not review or sandbox plugin code, and listings on herdr.dev are not
reviewed either; a plugin runs as your user with your environment, like any editor or
shell extension. Its own guidance is to read the manifest and the scripts before you
install, and this plugin is built to make that short: `herdr-plugin.toml` names every
command it can run, each is a bash script in `bin/` that does one thing, and
`herdr plugin install` shows you the startup command (`bin/beam-reconcile.sh`) before
it registers anything. To run the revision you read rather than whatever `main` holds
later, pin a release tag: `herdr plugin install jsabo/herdr-beams --ref <release-tag>`.
