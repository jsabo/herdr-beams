# Contributing

Thanks for looking. This repo is small on purpose: seven bash scripts, a manifest, a
demo, and a test suite that runs offline.

## Before you open a pull request

```sh
brew install bats-core shellcheck      # apt: bats shellcheck jq
tests/run.sh
```

That runs shellcheck, `bash -n` and the bats unit tests under `tests/unit/`. Every
script runs against fake `tsh`, `herdr` and `ssh` commands in `tests/fakes/`, which
record each call, so the tests assert on the exact command lines a script issues and
on every question a popup can ask. Add or change a test with every behaviour change.

When a change touches what the real commands return, also run the live test once. It
creates one Beam and deletes it:

```sh
HERDR_BEAMS_INTEGRATION=1 tests/run.sh
```

Then open the entry you changed for real:

```sh
herdr plugin link "$(pwd)"
herdr plugin action invoke herdr-beams.<id>
herdr plugin log list --plugin herdr-beams
```

## Rules of the house

The conventions the scripts follow are in [AGENTS.md](AGENTS.md); they apply to
people as much as to coding agents. The ones that matter most:

- bash, `tsh`, `ssh`, `jq` and coreutils only. No helper libraries, no second
  language, no build step.
- Nothing in the repo names a person, a tenant or a home directory. Examples use
  `<tenant>.beams.sh`.
- Anything that asks a question belongs in a popup pane and goes through `ask` or
  `ask_key`. Actions run without a terminal and must finish on their own.
- Colour and glyphs come from the helpers in `bin/common.sh` (`header`, `ok`, `busy`,
  `off`, `card_open`, `hints`, …), never from raw escape codes, and they switch off
  when stdout is not a terminal.
- Bump `version` in `herdr-plugin.toml` and add a line to [CHANGELOG.md](CHANGELOG.md)
  when behaviour changes. README changes go with any user-visible change.

## Screenshots

The README's images live in `assets/`. Capture them with herdr's sidebar visible, in
a fresh workspace with an empty shell behind the popup (so nothing unrelated is in the
frame), on a tenant whose name does not need to be hidden, at the default terminal
size. Crop to the herdr window. Keep each under 1 MB.

| File | What is on screen | How to get there |
|---|---|---|
| `assets/new-beam.png` | The New Beam popup at its question, four ticked phases and the Beam's card above it, the new machine in the sidebar | `ctrl+alt+b` (or `herdr plugin action invoke herdr-beams.new`), wait about 20 s |
| `assets/status.png` | The status popup with two or more cards | With a Beam from the step above, `ctrl+alt+s` |
| `assets/agent-done.png` | The sidebar with the Beam's agent marked `done`, no popup | `ctrl+alt+a`, give a short prompt ("Reply with the single word: ready. Do not run tools."), close the popup with any key, wait for the sidebar to flip to `done` |

Remove the Beam afterwards with the `rm` popup.
