# Instructions for agents working on herdr-beams

This repo is a herdr plugin plus a README. It is public. Everything here runs on the
user's laptop, never inside a Beam.

## Structure

- `herdr-plugin.toml` at the root is the plugin manifest, so `herdr plugin install
  jsabo/herdr-beams` works without a subdirectory.
- One bash script per pane under `bin/`. Name it after the pane id (`beam-new.sh`
  for pane `new`). Every pane also has an `[[actions]]` entry with the same id whose
  command is `bin/beam-open.sh <id>`, so keybindings can be `plugin_action` bindings
  and `herdr plugin action invoke herdr-beams.<id>` opens the popup. Every pane and
  action carries a `description`; `tests/unit/manifest.bats` checks all of this.
- `docs/measured.md` holds every measurement (timings, behaviour observed on a live
  tenant), dated and with versions. The README quotes numbers from it and links to it;
  it carries no lab notes of its own.
- `assets/` holds the README's screenshots. They are captured by hand (see
  `CONTRIBUTING.md`); nothing generates them.
- `CHANGELOG.md` gets a line with every version bump.
- `bin/common.sh` is the only shared code; every script sources it and calls
  `require_config`, except the reconcile hook, which must stay quiet without config.
- `tests/unit/<script>.bats` per script, `tests/fakes/` and `tests/fixtures/` for the
  offline doubles, `tests/integration/` for the opt-in live run. `tests/helpers.bash`
  has `run_script` (no terminal, like a scripted call) and `run_interactive` (answers
  fed on stdin, as if someone were at the keyboard of a popup).
- `demo/demo.sh` is the scripted walkthrough. It follows the same rules as `bin/`,
  only calls the `bin/` scripts and `herdr --machine`, and must keep passing
  `tests/unit/demo.bats` in `DEMO_AUTO=1` mode.
- `skills/herdr-beams/SKILL.md` is for coding agents that use herdr, not for humans.
- No generated files. No `node_modules`, no build step.
- Nothing in the repo may name a person, a tenant, or a home directory. Tenant,
  login and agent settings come from the plugin's `env` file; examples use
  `<tenant>.beams.sh`.

## Required validation before committing

```shell
tests/run.sh
```

That runs shellcheck, `bash -n`, and the bats unit tests under `tests/unit/`, which
exercise every script against fake `tsh`, `herdr` and `ssh` commands in
`tests/fakes/` (`brew install bats-core shellcheck`). Add or change a test with every
behaviour change; the fakes record each call in `$FAKE_LOG`, so assert on the exact
command lines the script issues.

When a change touches what the real commands return, also run the live test once.
It creates one Beam and deletes it:

```shell
HERDR_BEAMS_INTEGRATION=1 tests/run.sh
```

Then open the entry you changed for real: `herdr plugin link "$(pwd)"`, then
`herdr plugin pane open --plugin herdr-beams --entrypoint <id>`, and read
`herdr plugin log list --plugin herdr-beams`.

## Conventions

- Call herdr only through `$HERDR_BIN_PATH`; it points at the running binary.
- The Beam list and the machine list are fetched once per run into `BEAMS_JSON` and
  `MACHINES_JSON` (`load_lists`). After a change, call `refresh_beams` /
  `refresh_machines` or patch the cache (`remember_beam`, `forget_beam`); never shell
  out to `tsh beams ls` or `herdr machine list` directly in a script.
- `quick_reconcile` runs at the top of every pane. It may only use the two cached
  lists and `herdr machine remove`; no SSH, no `machine add`. Adds belong to the
  startup hook. One exception: `new` starts `tsh beams add` first and reconciles
  while Teleport provisions, because the listing fits inside that wait.
- A pane ends when its own work is done. It never waits on an agent (the agent list
  in the sidebar shows working and done) and never probes what the sidebar already
  shows (the machine dot is reachability). If a step will be silent for more than a
  couple of seconds, a `busy` line says what it is waiting for.
- Calls that do not depend on each other run at once (`&` into a temp file, then
  `wait $pid || die`). A test for such a pair asserts that both calls happened, not
  their order. `docs/measured.md` has what each call costs; cite it when trading
  one call for another.
- The plugin's ssh calls go through `beam_ssh` so they share one connection per Beam.
- Durable state goes in `$HERDR_PLUGIN_STATE_DIR`, user settings in
  `$HERDR_PLUGIN_CONFIG_DIR`. Never write into the plugin root; GitHub installs
  replace it.
- Actions run without a terminal and must finish on their own. Anything that asks the
  user a question belongs in a popup pane.
- A popup closes with its process, so `common.sh` installs an EXIT trap (`finish`)
  that keeps a failure on screen until a key is pressed whenever someone is at the
  keyboard (`interactive`: a terminal, or `BEAMS_INTERACTIVE=1` in tests). A script
  that installs its own EXIT trap ends it with `finish $rc`. Set `FAIL_HINT` while a
  failure would leave something behind, such as a Beam without a sidebar entry.
- Questions go through `ask` and `ask_key`, never a bare `read -p`: the prompt is
  printed whatever stdin is, and end-of-file leaves the answer empty instead of
  ending the script. Every y/N or menu path gets a `run_interactive` test, and a
  `hints` line ("y delete it · any other key keep it") goes right before it.
- A y/N confirmation is guarded by `must_confirm`, not `interactive`. `beam-open.sh`
  opens every action's pane with `--env BEAMS_YES=1`, so a keybinding or `herdr
  plugin action invoke` acts without asking while the plugin menu still asks. The
  env file is sourced after the environment, so `BEAMS_YES=0` in it is the user's
  off switch. Every confirmation gets a `run_bound` test showing it is skipped and
  one showing `BEAMS_YES=0` brings it back. Questions that collect
  a value (label, prompt, protocol, service) stay on `interactive`.
- The look is the helpers in `common.sh` and nothing else: `header` as the first
  line of every pane (before `quick_reconcile`, so its messages sit under it),
  `ok`/`busy`/`off`/`bad`/`note` for status lines (`● ◐ ○ ✗`), `card_open`/`card_line`/
  `card_close` for one Beam, `phase` for a timed step, `show_cmd` for a copyable
  command, `hints` for keys. No raw escape codes in a script; the `C_*` variables
  are empty when stdout is not a terminal or `NO_COLOR` is set, so tests and agents
  see plain text. Cards leave the right edge open: no column arithmetic.
- `pick_beam` checks an explicit Beam id against the list; scripts do not check again.
- The demo numbers its steps as they run. The talk tracks in `demo/README.md` must
  match the headings in `demo/demo.sh`, for both stories.
- Scripts are bash with `set -euo pipefail` and use only `tsh`, `ssh`, `jq` and
  coreutils. Do not add helper libraries or a second language.
- Bump `version` in the manifest when behaviour changes, with a `CHANGELOG.md` line.
  Keep `min_herdr_version` at the oldest herdr whose CLI the scripts actually use.
- README changes go with any user-visible change. Keep the README free of notes to
  ourselves; errors and their fixes live under Troubleshooting only.

## Beams rules that bite

- `tsh beams` acts on the active tsh profile. Every script resolves the proxy from
  `$BEAMS_PROXY` and passes `--proxy`; it never assumes the active profile.
- A Beam is addressed over SSH as `beams@<uuid>.<tenant>`. The short id
  (`neon-panel`) is not an SSH hostname. Both come from `tsh beams ls -f json`.
- Beams expire after 24 hours. Treat the state file as a cache and reconcile against
  `tsh beams ls` before acting.
- `tsh beams exec` re-splits the command on the remote side, so pipes and quotes do
  not survive it. Use `ssh beams@<uuid>.<tenant> '<command>'` for anything with a pipe.
- Publishing is port 8080 only and one app per Beam.
- Do not put internal hostnames, other tenants or links to private repositories in
  this repo.
