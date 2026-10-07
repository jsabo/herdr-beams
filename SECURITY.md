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
- `herdr machine add|remove|status|list` and `herdr --machine <beam> …`.

On the Beam, once per Beam and only when missing:

- `curl -fsSL https://herdr.dev/install.sh | sh` to install herdr into `~/.local/bin`.
- `herdr integration install <BEAM_AGENT_KIND>` so herdr sees the agent's state.
- A section `## Inside a Beam (added by herdr-beams)` appended to `~/.claude/CLAUDE.md`
  and `~/AGENTS.md`. The text is `beam_notes` in `bin/common.sh`.

## What it stores

- Your settings in `$(herdr plugin config-dir herdr-beams)/env`: the tenant name and,
  optionally, the SSH login, agent kind and agent arguments.
- A cache of the last Beam list (`beams.json`) in herdr's plugin state directory.
- Machine entries in herdr's own machine list, one per Beam, labelled with the Beam id.

No credentials. `tsh` holds your Teleport login; the Beam holds a delegated identity
that Teleport issues and renews. The plugin never reads either.

## Agents run with permission prompts off

`BEAM_AGENT_ARGS` defaults to `--dangerously-skip-permissions`. The Beam is the
boundary: an isolated microVM with a delegated identity that carries a subset of your
roles, Teleport's role-based access control (RBAC), and an audit log of every SSH,
database and inference call. There is nobody at the keyboard of a headless agent to
answer prompts. If you want the prompts anyway, set `BEAM_AGENT_ARGS=""` in the `env`
file.

## Reporting

Open a GitHub issue for anything that is not sensitive. For a vulnerability, use
GitHub's private vulnerability reporting on this repository. For an issue in Teleport
Beams itself, see Teleport's security policy at
https://github.com/gravitational/teleport/security/policy.
