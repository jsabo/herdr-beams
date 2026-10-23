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

**With the Beam-side plugin install (0.9.0, measured 2026-10-22, herdr 0.9.5 on the
Beam, Teleport 18.11.2, one run):** 19.5 s in all, and the phase lines put
**1.2 s** of that in `herdr plugin install --yes jsabo/herdr-beams` on the Beam
(8.3 s provisioning, 3.5 s to SSH, 1.2 s herdr and the integration, 1.2 s this
plugin, 5.3 s herdr's server start). The install was of the published checkout, so
the number stands for any revision of this repository. Two things that run came out
of that measurement:

- `herdr plugin install` needs `--yes` when stdin is not a terminal
  (`src/cli/plugin.rs:147`), which is always the case here.
- It prints its whole manifest preview to **stderr** even on success, about 30
  lines. The setup program holds that back and shows it only if the install
  fails, or it would fill the popup.

The plugin's ssh calls to one Beam share a connection (`ControlMaster`), and the
install, the integration and the notes travel in one SSH session, so a new Beam costs
one readiness probe plus one session.

## The sidebar label (2026-10-07, herdr 0.9.3)

- A saved machine has one visible field in the machines rail, its label. `herdr
  machine add --help` and `machine rename --help` take nothing else, `machine list
  --json` returns `id, label, target, session, enabled, selected`, and the v0.9.3
  config reference has row layouts for `ui.sidebar.agents` and `ui.sidebar.spaces`
  only. So `beam/<id>` is how a Beam is told from an ordinary host.
- `herdr machine rename` wants the profile id first: `rename <profile-id> --label
  <label>`. The binary's `--help` prints `--label <LABEL> <PROFILE_ID>`, and that
  order is rejected with `usage: herdr machine rename <profile-id> --label <label>`.
  The 0.9.0 docs (`connecting-machines`) show the order that works. Renaming the one
  existing profile from the startup hook took 3.9 s end to end, the Beam listing
  and two machine listings included.
- A `/` in a label is accepted by `machine add`, `machine rename` and as the
  `--machine` selector (`herdr --machine beam/<id> pane list`).

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

## What a launched agent leaves on screen (2026-10-22)

Read back with `herdr --machine beam/<id> pane read <pane>` on a live Beam, both
agents launched by the `agent` pane:

- **Claude Code clears the screen when it starts.** Its pane's visible buffer
  begins at the `Claude Code v2.1.258` banner: the shell prompt and the launch
  command `agent start` typed are gone.
- **Codex draws inline and keeps them.** Its pane showed two prompt lines, the
  detection hint and then `codex --model ... --sandbox workspace-write
  --ask-for-approval on-request -c sandbox_workspace_write.network_access=false`,
  above its own header box. 0.9.0 clears the pane from inside the hint so the two
  match.
- **`clear` cannot do that clearing.** A herdr pane runs with
  `TERM=xterm-ghostty` (`src/pane.rs:72,105`), and the Beam image's Debian has no
  terminfo entry for it: `TERM=xterm-ghostty clear` on the Beam prints
  `'xterm-ghostty': unknown terminal type.` and clears nothing. The hint writes
  the escape sequence instead.
- **The agent row's third line is the user's row config, not a herdr detection.**
  Measured on the live Beam: Claude Code sets a terminal title (`✳ Claude Code`,
  then its current task), and the Codex pane's title read `beams`. The reason
  for that `beams` is below (2026-10-23) and is not "Codex leaves the shell's
  title", which this entry first claimed. `display_agent` is the wrong field to
  reach for either way: it feeds the row's *first* line, where the agent name
  goes (`src/client/shell/agent_sidebar.rs:275-280`), and setting it replaced
  `codex` with a truncated `OpenAI C…`.
- **A plugin-reported token is the field that works.**
  `herdr pane report-metadata --source herdr-beams --token harness=...` sets it,
  a row reads it as `{ token = "$harness" }`, and herdr resolves an unknown token
  name from the pane's reported tokens (`src/ui/sidebar/tokens.rs:107-112`). The
  `$` is required in the config and absent from the reported name
  (`src/config/sidebar.rs:228-241`); without it `herdr config check` fails with
  "custom tokens must start with `$`" and falls back to the default rows.
  `--source` accepts ASCII letters, digits, colon, dot, underscore and hyphen, up
  to 80 characters (`src/app/api_helpers.rs:210-226`).

## What the sidebar can show, and herdr's own defaults (read 2026-10-22, herdr 0.9.5)

- **The shipped row layouts**, which this plugin's README follows except that it
  gives both harnesses the title row (2026-10-23 below): agents
  `[["state_icon", "machine", "workspace", "tab"], ["agent"]]`, with
  `claude` overridden to put `terminal_title_stripped` between those two rows;
  spaces `[["state_icon", "workspace"], ["branch", "git_status"]]`
  (`src/config/sidebar.rs:440-476`, and `herdr --default-config`). The location
  goes on the first row and the agent under it, which is what keeps a long
  machine label from pushing the rest out of view.
- **Agent row tokens**: `state_icon`, `state_text`, `machine`, `workspace`,
  `tab`, `pane`, `agent`, `terminal_title`, `terminal_title_stripped`, plus
  `$name` for a token reported on the **pane**.
- **Space row tokens**: `state_icon`, `state_text`, `workspace`, `branch`,
  `git_status`, plus `$name` for a token reported on the **workspace**. There is
  no agent token: `SpaceTokenContext` carries no agent name, kind or list
  (`src/ui/sidebar/tokens.rs:124-131`), and a space row's `state_text` is always
  one of `working|blocked|done|idle|unknown`. Naming what runs in a workspace is
  therefore only possible through a reported token, which is what
  `herdr workspace report-metadata --token agent=<name>` is for.
- **A pane token never reaches the machines rail** and a workspace token never
  reaches an agent row: the two stores are separate
  (`src/app/api/workspaces.rs:301-303` versus `src/app/api/panes.rs:1701`).
- The `machine` token is absent whenever the client has one endpoint, so it costs
  nothing until a Beam exists; with a Beam present herdr fills it with `Local`
  for laptop agents, which the `{ equals = "Local", hide = true }` rule drops.
- Token limits: a reported value is trimmed to 80 characters, keys are
  `[A-Za-z0-9_-]` up to 32 characters, 16 keys per report and 32 per resource
  (`src/app/api_helpers.rs:205-275`). Tokens do not survive a server restart.

## The Codex agent row's headline (2026-10-23, codex-cli 0.152.1, herdr 0.9.5)

The `beams` recorded above is Codex's own terminal title, not the shell's. Read
in the Codex source at the Beam's version, tag `rust-v0.152.1`:

- **Its default title items say nothing on a Beam.**
  `DEFAULT_TERMINAL_TITLE_ITEMS = ["activity", "project-name"]`
  (`codex-rs/tui/src/chatwidget/status_surfaces.rs:27`). `project-name` for
  `/home/beams` is `beams`, and `activity` is a braille spinner frame.
- **Codex already generates the label we want.** On the first user message in an
  unnamed thread it runs a hidden turn for a thread title, capped at 36
  characters and prompted for "under five words where possible"
  (`codex-rs/tui/src/app/thread_title.rs:22,219`, fired from
  `codex-rs/tui/src/app/thread_routing.rs:2046-2075`). The item that shows it is
  `thread-title`; the `thread-name` item that upstream `main` has since added to
  the default does not exist here
  (`codex-rs/tui/src/bottom_pane/title_setup.rs:32-93`).
- **`-c` values parse as TOML**, arrays included
  (`codex-rs/utils/cli/src/config_override.rs:21-36`), so a launch can ask for
  the items it wants without writing config on the Beam.

Measured on the live Beam with `herdr --machine beam/<id> agent list`, one
Claude agent and two Codex agents, the second launched after the change:

| agent | `terminal_title` | `terminal_title_stripped` |
|---|---|---|
| `claude` | `✳ Weather in Glens Falls, NY` | `Weather in Glens Falls, NY` |
| `codex` (before) | `beams` | `beams` |
| `codex-2` (after) | `Check weather in GF NY` | `Check weather in GF NY` |

- **Neither row shows a spinner.** herdr strips one leading `U+2800`–`U+28FF`
  frame (Codex's) or one of Claude's `✳ ✢ ✻ ◐ ◓` glyphs when whitespace follows
  (`herdr/src/terminal/title.rs:12-15`).
- **An unnamed thread puts its id in that title**: `thread-title` falls back to
  the thread UUID (`status_surfaces.rs:776-786`; read in the source, not caught
  live). herdr's row rules have no regex — `equals`, `contains`, `starts_with`,
  `gt`, `lt`, with `ignore_case`
  (`herdr/src/config/sidebar/rules.rs:17-24`) — so `{ starts_with = "01",
  hide = true }` is what hides a v7 UUID minted this decade without hiding a
  real title.
- **What is still not parity.** Claude Code rewrites its title as the work
  changes; Codex names a thread once, because the trigger requires
  `thread_name().is_none()` (`thread_routing.rs:2046`). Turn five shows the
  label from turn one. A per-turn Codex line would need a `Stop` or
  `UserPromptSubmit` hook reporting a token, which costs a hook file on every
  Beam and a second `hooks.state` trust entry on the launch path.

## Glyphs for the harnesses (2026-10-22)

Parsed `MesloLGMDZNerdFontMono-Regular.ttf` (the terminal's font) on this Mac:
13,084 codepoints, every standard Nerd Font set complete (Material Design
6896/6896, Font Awesome 768/768, Devicons 198/198, Seti 185/185, Font Logos
118/118, Codicons 439/447). Searched all 12,855 named glyphs in its `post` table
for `openai|anthropic|claude|gpt|copilot|robot|brain|sparkle|chat`:

- **No OpenAI or Anthropic logo exists.** The nearest are `cod-copilot`
  (U+EC1E, a different vendor), `cod-sparkle` (U+EC10), `fa-robot` (U+EE0D),
  `md-robot` (U+F06A9) and `fa-brain` (U+EE9C) — stand-ins nobody reads as the
  brand.
- **Each tool's own mark exists but does not pay for itself.** Claude Code puts
  `✳` (U+2733, present, and plain Unicode) in the terminal title it sets, and
  Codex's header mark is `>_`. Tried on the live sidebar: a mark on the identity
  line costs a glyph plus a ` · ` separator, four columns, and pushed
  `beam/retro-rover` into `beam/re…` on exactly the rows that carried one — to
  say what the agent name (`claude-2`, `codex-2`) already says, since the plugin
  names agents after their harness. Reverted; the row carries no mark.

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

## The Beams keys on a Beam (0.9.0)

Verified on a live Beam on 2026-10-22 (herdr 0.9.5 on the Beam, Teleport 18.11.2):
`herdr plugin install --yes` over SSH put this plugin on a fresh Beam, the key block
reached the Beam's `~/.config/herdr/config.toml`, the plugin's `env` there carried
`BEAM_SELF_ID` and `BEAM_SELF_UUID`, and the Beam's own herdr published the plugin's
actions to `herdr --machine beam/<id> plugin action list`. What a keypress then does
on the Beam could not be run end to end, because a Beam installs the published
revision and that is still 0.8.7; `tests/integration/live.bats` skips that case
until 0.9.0 is on GitHub.

**Which binding wins a collision** (read at 0.9.x, and it is the opposite of what
it looks like): herdr parses user bindings in a first pass and its own defaults in a
second (`src/config/keybinds.rs:651`), each binding claims its key as it is parsed,
and a default that lands on an already-claimed key is dropped with **no diagnostic**
(`:1099-1102`). So a `[[keys.command]]` on `prefix+s` works and herdr's Settings key
silently stops existing, and `herdr config check` still prints `config: ok`. Hence
the plugin's nine keys all avoid the defaults.

The rest is read in herdr's own source at 0.9.x, not measured on a tenant:
`apply_snapshot_keybindings` replaces the live `[[keys.command]]` list with the
selected machine's published commands on every machine switch
(`src/client/shell/config.rs:228-278`, re-run from `state.rs:1397`), which is why a
Beam's keys have to come from that Beam's herdr. A popup belongs to the server that
owns it and is delivered only in that machine's pane-update stream
(`src/app/state.rs:877`, `src/client/endpoint/message_policy.rs:19-45`), and a
second one fails with "popup already open" (`src/app/popup.rs:116`). `--machine`
forwards only API-backed commands, with `plugin` limited to
`link|unlink|enable|disable|list|action|log|logs|pane` and `server` to
`stop|reload-config|agent-manifests|reload-agent-manifests`
(`src/cli/target.rs:291-319`); `plugin install` and `plugin uninstall` are not
among them, which is why the Beam-side install goes over SSH.

Measured since: the Beam-side install itself, 1.2 s, under
[The `new` popup](#the-new-popup) above. The demo's step 2 (18 s) and its 52 s whole
story have not been re-run, so they are still the pre-0.9.0 numbers; expect about a
second and a half more.

Still to measure on a live Beam:

- Whether `tsh beams ls` and `tsh beams publish` work inside a Beam under the
  delegated identity. They are plain API calls, not certificate reissues, so they
  are expected to work, but `disallow-reissue` has only been mapped for the
  commands listed under the delegated identity above. The Beam-side `status` pane
  falls back to the Beam's own settings and `beamctl` either way, and the
  Beam-side `publish` pane names the laptop if `tsh` refuses.
- Whether `herdr server reload-config` on a Beam is enough for an attached client
  to pick up its new command list without switching machines away and back. A new
  Beam does not depend on this, because its herdr server starts after the key block
  is in place; the `keys` pane does.

## Expected, not yet measured

Reconnect after laptop sleep uses herdr's own backoff and needs no new login while the
`tsh` certificate is valid.
