---
name: herdr-beams
description: Run coding agents inside Teleport Beams (ephemeral sandbox VMs) from herdr. Use when asked to start an agent in a sandbox, in a Beam, or away from the laptop, or to list, publish or remove Beams.
---

# Running agents in Teleport Beams from herdr

A Beam is a short-lived Linux VM from Teleport Cloud. It carries the user's delegated
Teleport identity, a proxied model endpoint (`ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL`,
no API keys), and expires after 24 hours. herdr treats each Beam as a saved SSH
machine labelled `beam/<beam-id>`, so every herdr command works there with the
`--machine beam/<beam-id>` prefix (the label is the selector; the bare id is not).

## Check first

```bash
test "${HERDR_ENV:-}" = 1 || echo "not inside herdr"
herdr machine list --json          # Beams appear as beam/<beam-id>; the target holds the uuid
herdr plugin list                  # the herdr-beams line shows where the plugin lives
```

The plugin's scripts live in its root: `$HERDR_PLUGIN_ROOT` inside a plugin pane,
otherwise the path `herdr plugin list` prints for `herdr-beams`. The scripts `cd` to
that root themselves, so call them by path from anywhere:

```bash
ROOT="${HERDR_PLUGIN_ROOT:-<the path herdr plugin list shows for herdr-beams>}"
```

If the plugin's config has no `BEAMS_PROXY`, stop and ask the user for the tenant
(`<name>.beams.sh`). Never run `tsh login` for the user.

## Create a Beam and put an agent in it

The plugin's scripts do the whole sequence. Always give them `</dev/null`: with no
terminal they never ask a question, never wait for a key, and exit non-zero with
the reason on stderr. (At a keyboard, a failure stays on screen until a key is
pressed, which would block you.)

```bash
bash "$ROOT/bin/beam-new.sh" </dev/null                       # new Beam, herdr installed, machine added
bash "$ROOT/bin/beam-agent.sh" <beam-id> <workspace-label> "<first prompt>" </dev/null
```

`beam-agent.sh` needs a Beam that exists: with none it fails with `no Beams`, so run
`beam-new.sh` first. An unknown Beam id fails with `no Beam named <id>` before anything
runs. The script names agents after their kind (`claude`, then `claude-2`, ...) and
puts each in a new workspace created with `--no-focus`. Leave the Beam's default `~`
workspace alone and focused: herdr clears `done` for a viewed pane, and on the Beam's
headless server the focused pane counts as viewed, so an agent started in the default
workspace goes from `working` straight to `idle` with no `done` and no notification.
The pieces, if you need them:

```bash
herdr --machine beam/<beam-id> workspace create --cwd '~' --label <label> --no-focus   # .result.root_pane.pane_id
herdr --machine beam/<beam-id> agent start claude --kind claude --pane <pane-id> -- --dangerously-skip-permissions
herdr --machine beam/<beam-id> agent prompt claude "<prompt>" --wait --timeout 600000
herdr --machine beam/<beam-id> agent read claude
```

Agents in a Beam run with permissions skipped by design; the sandbox, Teleport RBAC
and session recording are the guardrails. Do not add approval prompts.

## What is true inside a Beam

`beam-new.sh` appends these to the Beam's `~/.claude/CLAUDE.md` and `~/AGENTS.md`, so
an agent started there already knows them. When you write a prompt for a Beam agent,
do not ask it to discover any of this:

- `tsh` holds a delegated identity that cannot reissue certificates, so `tsh db
  connect`, `tsh proxy db|app` and `tsh kube login` fail by design; `tsh login` is
  not an option.
- Databases are reached only over VNet with a plain client, and only postgres, mysql,
  sql-server and cockroachdb. Other engines resolve to the public proxy and hang.
- The database user is the full Teleport username; pass it with `user=` / `-u`, not
  inside a URI.
- Not installed: mysql, kubectl, mongosh, redis-cli, docker. apt works.
- The identity is renewed in the background; `tsh status` always shows about an
  hour left and that is not a deadline.

## Everything else

```bash
bash "$ROOT/bin/beam-status.sh" </dev/null              # Beams, expiry, sidebar entry
bash "$ROOT/bin/beam-services.sh" <beam-id> </dev/null  # beam-init services (beamctl list)
bash "$ROOT/bin/beam-publish.sh" <beam-id> http </dev/null  # expose port 8080 as a Teleport app
bash "$ROOT/bin/beam-rm.sh" <beam-id> </dev/null        # delete the Beam and its profile
bash "$ROOT/bin/beam-rm-all.sh" </dev/null              # delete every Beam and profile (no question without a terminal)
```

Long-running processes inside a Beam that are not agents (a dev server, a database)
belong to beam-init, not to a herdr pane:

```bash
ssh beams@<uuid>.<tenant> 'beamctl start --name web -- python3 -m http.server 8080'
```

Only port 8080 can be published, and only one app per Beam.
