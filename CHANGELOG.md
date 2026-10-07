# Changelog

## 0.7.0 (2026-10-07)

- A Beam's sidebar entry is labelled `beam/<id>` (`beam/neon-panel`) instead of the
  bare id, so the machines rail tells a Beam from an ordinary SSH host at a glance.
  The label is also the `herdr --machine` selector, so copyable commands and the skill
  now read `herdr --machine beam/<id> …`. `BEAM_LABEL_PREFIX` in the settings file
  changes the prefix; an empty value gives bare ids again.
- The startup hook renames entries made by earlier versions in place
  (`herdr machine rename`); nothing is removed and re-added. The scripts now find a
  Beam's profile by the uuid in its target rather than by its label, as herdr's own
  docs advise, so a relabelled entry is still recognised.

## 0.6.1 (2026-10-06)

- Ctrl+C is the way out of any popup. Every script now traps it and exits 130, and
  the exit handler treats 130 as a cancel: the popup closes at once with no
  `failed (exit 130)` line. The one exception is a cancel after `new` has created a
  Beam but before it is in the sidebar: the hint about the half-made Beam stays on
  screen until a key is pressed, where before it vanished with the popup (bash runs
  the exit trap with status 0 when Ctrl+C lands on a question or a foreground call).

## 0.6.0 (2026-10-06)

- A keybinding or `herdr plugin action invoke` opens a popup with its y/N question
  already answered: `rm` and `rm-all` delete at once, and `agent` with no Beams
  creates one without asking. The actions open panes with `--env BEAMS_YES=1`
  (`bin/beam-open.sh`); the plugin menu opens them without it and still asks.
  Questions that collect a value (workspace label, first prompt, protocol, service)
  are unchanged. `BEAMS_YES=0` in the settings file brings the questions back for
  keybindings as well.
- The `agent` popup no longer asks "Start a claude agent in it now?" after creating
  a Beam for you: `beam-new.sh --agent` hands straight back to it. Opened on its own,
  `new` still ends with that offer, which is also its close key.
- The `agent` popup no longer offers to wait for the first result. The wait printed
  nothing until the agent settled and then a forty-line snapshot, while the agent
  list in the sidebar had already flipped to `done`. The pane now closes once the
  prompt is sent; the demo keeps its own wait.
- The `status` popup no longer probes each Beam with `herdr machine status` (2.4 s
  per Beam, measured): the dot on the sidebar entry is that same fact. The pane now
  costs one Beam listing and shows whether each Beam has a sidebar entry.
- `new` fetches the Beam list while Teleport provisions the Beam instead of before
  (1.4 s off the critical path), and says what it is waiting for during the SSH
  wait and herdr's server start, the two silences in its 18 s.
- `agent` lists the existing agents (for the name) while it creates the workspace,
  two forwarded calls at once instead of in turn (0.9 s).
- `docs/measured.md` has the per-call timings these numbers come from.
- `min_herdr_version` is 0.9.1 again: `herdr machine status`, the one 0.9.2 command,
  is no longer used, and everything else the scripts call is in 0.9.1.
- README: the example bindings are prefix chords (`prefix+shift+b`, `prefix+a`,
  `prefix+s`, `prefix+d`, `prefix+shift+q`) instead of `ctrl+alt` direct chords. Every
  public herdr plugin surveyed that suggests keys suggests `prefix+` ones, and a prefix
  chord cannot be taken by anything outside herdr. `ctrl+alt+d` is Magnet's "Left
  Third" (it resized the terminal instead of opening the popup) and herdr's keyboard
  guide lists `ctrl+alt+a` and `ctrl+alt+s` as owned by KDE and Konsole.

## 0.5.0 (2026-10-06)

- New `rm-all` popup and action: lists every Beam on the tenant, asks once, then
  deletes them all and their sidebar entries. One keybinding tears everything down.
- README: example bindings for `rm` (`ctrl+alt+d`) and `rm-all` (`ctrl+alt+x`), and
  the way in and the way out in two keys.

## 0.4.0 (2026-10-06)

- Popups have one look: a header with the tenant, `● ◐ ○ ✗` status lines, a card per
  Beam (`╭─ neon-panel ─`), ticked phases with timestamps, and a key-hint line before
  every question. Colour only on a terminal; `NO_COLOR` is honoured.
- The status popup shows one card per Beam with reachability, region, expiry (`in 2h
  14m`) and SSH address, instead of a table and a summary line.
- Every pane has an action of the same id (`herdr-beams.new`, …), so keybindings can
  use `type = "plugin_action"` and `herdr plugin action invoke` opens a popup from any
  shell. Every pane and action has a description.
- README rewritten for an outside reader: install first, what the plugin runs on your
  machine, limitations, uninstall. Measurements moved to `docs/measured.md`.
- Added `SECURITY.md`, `CONTRIBUTING.md`, this changelog and a CI workflow that runs
  `tests/run.sh`.

## 0.3.0 (2026-10-06)

- A failing popup stays open with the reason until a key is pressed.
- The agent popup offers to create a Beam when none exists.
- The demo names its story and numbers its steps; `DEMO_PROMPT` runs a task story
  without the app steps; `DEMO_WORKSPACE` names the workspace.
- The agent popup keeps the Beam's default workspace focused so an agent's `done`
  state is not cleared; the `new` popup seeds Beam notes into the Beam's `CLAUDE.md`
  and `AGENTS.md`.

## 0.2.0 (2026-10-05)

- Every popup drops expired Beams on entry; the Beam and machine lists are fetched
  once per run; the plugin's `ssh` calls share one connection per Beam.
- The `new` popup prints a timestamp per phase. The agent popup can wait for the
  first result. The demo times every step.
- bats unit suite against fake `tsh`, `herdr` and `ssh`; opt-in live test.

## 0.1.0 (2026-10-05)

- First release: create Teleport Beams and run coding agents in them from the herdr
  sidebar.
