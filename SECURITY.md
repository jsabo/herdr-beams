# Security

A herdr plugin is ordinary code that runs as your user, inherits your environment and
can call the full herdr CLI. herdr validates the manifest; it does not review or
sandbox plugin code. This file says exactly what herdr-beams does so you can decide.

## What it runs

On your laptop, the scripts in `bin/` call only `tsh`, `ssh`, `jq`, coreutils and the
running herdr (`$HERDR_BIN_PATH`):

- `tsh --proxy=<BEAMS_PROXY> beams ls|add|rm|publish`. The proxy is always the tenant
  you put in the plugin's `env` file; the active `tsh` profile is never assumed.
- `ssh beams@<uuid>.<tenant>` through your own SSH config, with `BatchMode=yes` and one
  shared connection per Beam (`ControlMaster`, socket under `/tmp/herdr-beams-*`).
- `herdr machine add|rename|remove|list` and `herdr --machine <beam> …`.

On the Beam:

- `curl -fsSL https://herdr.dev/install.sh | sh` to install herdr into `~/.local/bin`
  when no installation is found. Existing installations on PATH are reused.
- `herdr integration install <selected harness>` during preparation and before
  launches on existing Beams, so herdr sees the agent's state. A direct handoff
  from creation reuses the integration just installed.
- A section `## Inside a Beam (added by herdr-beams)` appended to `~/.claude/CLAUDE.md`
  and `~/AGENTS.md`. The text is `beam_notes` in `bin/common.sh`.

## What it stores

- Your settings in `$(herdr plugin config-dir herdr-beams)/env`: the tenant name and,
  optionally, the SSH login, agent kind, agent arguments and default profiles.
- Optional user profile overrides in the configuration directory's `profiles.json`.
- A cache of the last Beam list (`beams.json`) in herdr's plugin state directory.
- Machine entries in herdr's own machine list, one per Beam, labelled `beam/<id>`
  by default (configurable).

No credentials. `tsh` holds your Teleport login; the Beam holds a delegated identity
that Teleport issues and renews. The plugin never reads either.

## Agent permissions and delegated identity

Legacy launches without a profile default to Claude Code with
`--dangerously-skip-permissions`. Set `BEAM_AGENT_ARGS=""` in the `env` file to keep
that harness's permission prompts. Profile launches use their own approval and
sandbox settings; legacy arguments are not added to profile arguments.

Bundled Claude profiles use bypass approval. The bundled Codex profiles use
`never` or `on-request` approval with `workspace-write` sandboxing. Codex `never`
suppresses approval requests while retaining the selected sandbox. Profile
approval prompts may require opening the agent's pane. See the
[profile reference](docs/profiles.md) for allowed settings and overrides.

Harness permissions and Teleport authorization are separate controls. Beams
provides runtime isolation and delegated identity; harness settings govern what
the agent may execute within that environment. In the tested beta, a Beam's
delegation inherited the user's role set. Do not assume it receives a restricted
subset. Current Beams product workflows describe scoped roles and reviewed plans;
this plugin does not configure those workflows. See
[runtime compatibility](docs/architecture.md#runtime-lifecycle-and-compatibility).

## Reporting

Open a GitHub issue for anything that is not sensitive. For a vulnerability, use
GitHub's private vulnerability reporting on this repository. For an issue in Teleport
Beams itself, see Teleport's security policy at
https://github.com/gravitational/teleport/security/policy.
