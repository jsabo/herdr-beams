# Measured

Numbers in the README come from here. Everything below was measured on 2026-10-05 and
2026-10-06 on a `*.beams.sh` tenant running Teleport 18.11.2, with herdr 0.9.3 on macOS
(arm64) and the Beam image Debian 12 (x86_64). Re-measure when either version moves.

## The demo, unattended

Three runs of `DEMO_AUTO=1 demo/demo.sh` (the app story): 51 s, 52 s, 52 s.

| | Step | Time |
|---|---|---|
| 1 | Empty start: no Beams, no Beam machines | 1 s |
| 2 | New Beam created, herdr installed on it, machine in the sidebar | 18 s |
| 3 | Claude Code started in the Beam with a task, from the laptop | 9 s |
| 4 | The agent writes a Flask app and starts it as a `beamctl` service | 18 s |
| 5 | `beamctl list` shows it running; `curl` inside the Beam answers | 1 s |
| 6 | Port 8080 published as a Teleport application with its own URL | 2 s |
| 7 | Beam and sidebar entry removed | 1 s |
| | **Whole story** | **52 s** |

Of the 18 s in step 2, about 10 s is Teleport provisioning the microVM, 2 s is SSH
coming up, 1 s is installing herdr over a shared SSH connection, and 6 s is herdr
starting its server on the Beam. Step 4 is the model's time to write the app; it
varied from 16 s to 18 s across the runs.

## What one call costs (2026-10-06)

Each command the popups run, timed from the laptop against a live Beam on the same
tenant (herdr 0.9.3, Teleport 18.11.2), one run each unless noted:

| Call | Time |
|---|---|
| `tsh beams ls -f json` | 1.4 s |
| `herdr machine list --json` (local) | 0.02 s |
| `herdr --machine <beam> agent list` (two runs) | 0.9 s, 1.0 s |
| `herdr --machine <beam> pane list` | 0.9 s |
| `herdr machine status <beam> --json` | 2.4 s |

herdr multiplexes its own SSH to a machine (`ControlPersist=600` in
`src/remote/attach.rs`), so a forwarded call is about 0.9 s whether or not an earlier
one warmed the connection. What follows from the table:

- Every popup pays the 1.4 s Beam listing once, in `quick_reconcile`. `new` hides it
  behind the ten-second provisioning by starting `tsh beams add` first.
- `agent` ran the agent list and the workspace create in turn, 1.8 s; they now run
  at once, 0.9 s. Its other seconds are Claude Code starting (about 5 s) and the
  prompt (1.2 s), both on the Beam.
- `status` probed every Beam with `machine status`, 2.4 s even though the probes ran
  in parallel, to show a fact the sidebar's machine dot already shows. The probe is
  gone; the pane now costs the listing alone.
- Of `new`'s 18 s, the 10 s of provisioning is Teleport's and the 5 s of `herdr
  machine add` is herdr's remote discovery and server start (`prepare` in
  `src/remote/attach.rs`); neither can be shortened from the plugin.

## The `new` popup

Unattended, median of three: 19 s from no Beam to a reachable machine in the sidebar
(10 s provisioning, 2 s SSH, 1 s install, 6 s herdr server).

The plugin's ssh calls to one Beam share a connection (`ControlMaster`), and the
install, the integration and the notes travel in one SSH session, so a new Beam costs
one readiness probe plus one session.

## herdr inside a Beam

- The Beam's `herdr server` has process id (PID) 1 as its parent and stays up after
  the SSH session that started it closes. `herdr machine add` succeeds without a
  terminal once herdr is installed, because the installer puts it in `~/.local/bin`,
  which herdr checks.
- `agent prompt --wait` returns `done` only when the agent's workspace is not the
  focused one on the Beam: herdr clears `done` once a pane is viewed, and on the
  Beam's headless server the focused pane counts as viewed. The same prompt in the
  default `~` workspace went `working` → `idle` with no `done` and no notification;
  in a workspace created with `--no-focus` it stayed `done`. The `agent` popup
  therefore always creates a workspace and leaves `~` alone.
- `herdr integration install claude` on the Beam merges its hook into the
  pre-populated `~/.claude/settings.json`; the Beam's model list and
  `skipDangerousModePermissionPrompt` stay intact.
- `BEAM_AGENT_ARGS="--dangerously-skip-permissions --model opus"` is honoured: the
  agent's header reads `Opus 5` through the Beam's proxied endpoint, over the Sonnet
  pin in the image's `settings.json`.

## The delegated identity

- It is refreshed in the background: `tsh status` inside a Beam showed `Valid until`
  move from 00:41 to 02:01 Coordinated Universal Time (UTC) over 80 minutes, with the
  identity file rewritten at 01:01. An agent never has to log in again.
- It cannot reissue certificates: `tsh db connect`, `tsh db login`, `tsh proxy db`,
  `tsh proxy app` and `tsh kube login` fail with "identity is not allowed to reissue
  certificates".
- VNet inside a Beam hands addresses only to postgres and mysql on a cluster that also
  has mongodb, redis, oracle, cassandra and clickhouse; the rest resolve to the public
  proxy wildcard and clients hang until they time out.

## What the seeded notes save

The Beam image ships a `~/.claude/CLAUDE.md` (also `~/AGENTS.md`) that explains the
environment variables, the VNet database names and publishing. It leaves out what an
agent then spends its first minutes discovering: that the delegated identity cannot
reissue certificates, that only postgres, mysql, sql-server and cockroachdb have a
VNet path, that the database user is the full Teleport username, which clients are
not installed, and that the identity renews in the background. Left to find this out,
one agent spent seven minutes probing six database engines and installing two clients
before answering.

With the notes the `new` popup appends (`beam_notes` in `bin/common.sh`), an inventory
prompt (list the nodes, query postgres and mysql, list the apps) took 39 s from agent
start to `done`, 10 s of which was starting the agent.

## Ctrl+C in a popup (2026-10-06, bash 5.3.20, macOS)

Measured by running the scripts in a pseudo-terminal against the test fakes and
writing the Ctrl+C byte to it. Without an INT trap, bash runs the EXIT trap and then
dies of the signal; what the trap sees depends on where Ctrl+C landed:

| Ctrl+C lands on | `$?` in the EXIT trap | Popup |
|---|---|---|
| `read` (a question) | 0 | closes at once |
| a foreground call (`ssh`, `herdr machine add`) | 0 | closes at once |
| `wait` on a background call (`tsh beams add &`) | 130 | `failed (exit 130)`, waits for a key |

Status 0 means the exit handler could not tell a cancel from success, so the hint
about a Beam created but not yet in the sidebar (foreground phases of `new`) was lost
with the popup. With `trap 'exit 130' INT` in `common.sh` (0.6.1), all three land in
the handler as 130: the popup closes at once, and only a set `FAIL_HINT` keeps it
open. Verified the same way for all three cases after the change.

## Expected, not yet measured

Reconnect after laptop sleep uses herdr's own backoff and needs no new login while the
`tsh` certificate is valid.
