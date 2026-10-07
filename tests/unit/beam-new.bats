#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

host="beams@cccccccc-0000-4000-8000-000000000003.example.beams.sh"

@test "new: creates the Beam, waits for SSH, installs herdr, adds the machine, in that order" {
  echo 2 > "$FAKE_STATE/ssh-fail-count"
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Beam new-beam created (cccccccc-0000-4000-8000-000000000003)"* ]]
  [[ "$output" == *"SSH up"* ]]
  [[ "$output" == *"herdr 0.0.0-fake installed, claude integration and Beam notes in place"* ]]
  [[ "$output" == *"new-beam is in the sidebar"* ]]
  calls_in_order \
    "tsh --proxy=example.beams.sh beams add --no-console -f json" \
    "$host true" \
    "curl -fsSL https://herdr.dev/install.sh | sh" \
    "herdr machine add ssh://$host --label new-beam"
  # two failed probes, then one that succeeded
  [ "$(call_count "$host true")" -eq 3 ]
  grep -q "integration install claude" "$FAKE_LOG"
}

@test "new: one SSH session installs herdr, the integration and the Beam notes, before the machine add" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  calls_in_order "curl -fsSL https://herdr.dev/install.sh | sh" "herdr machine add"
  # install, integration, notes and version each appear once in the log ...
  [ "$(call_count 'install.sh')" -eq 1 ]
  [ "$(call_count 'integration install claude')" -eq 1 ]
  [ "$(call_count 'grep -qs "^## Inside a Beam"')" -eq 1 ]
  [ "$(call_count '"$HOME/.claude/CLAUDE.md" "$HOME/AGENTS.md"')" -eq 1 ]
  [ "$(call_count 'herdr" --version')" -eq 1 ]
  # ... and the readiness probes apart, there is exactly one ssh session to the Beam
  [ "$(grep -c "^ssh .*$host " "$FAKE_LOG")" -eq $(( $(call_count "$host true") + 1 )) ]
}

@test "new: a failure after the Beam exists names it and says how to remove it" {
  echo 99 > "$FAKE_STATE/ssh-fail-count"
  run_script beam-new.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not accept SSH"*"Beam new-beam exists without a sidebar entry"*"bash bin/beam-rm.sh new-beam"* ]]
}

@test "new: a failure before the Beam exists carries no such hint" {
  touch "$FAKE_STATE/not-logged-in"
  run_script beam-new.sh
  [ "$status" -eq 1 ]
  [[ "$output" != *"exists without a sidebar entry"* ]]
}

@test "new: at the keyboard, y hands over to the agent pane for the new Beam" {
  run_interactive beam-new.sh <<<$'y\n\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Start a claude agent in it now? [y/N]"* ]]
  grep -q "^herdr --machine new-beam workspace create --cwd ~ --label work --no-focus$" "$FAKE_LOG"
}

@test "new: from a keybinding the offer stays, because it is also the close key" {
  run_bound beam-new.sh <<<$'\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Start a claude agent in it now? [y/N]"* ]]
  ! grep -q "agent start" "$FAKE_LOG"
}

@test "new: --agent hands over to the agent pane without asking" {
  run_interactive beam-new.sh --agent <<<$'\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Start a claude agent in it now?"* ]]
  [[ "$output" == *"Workspace label [work]:"* ]]
  calls_in_order "herdr machine add" "herdr --machine new-beam workspace create --cwd ~ --label work --no-focus" "agent start claude"
}

@test "new: every phase line carries a timestamp" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^✓ \[\+ *[0-9.]+s\] ')" -eq 4 ]
}

@test "new: the plugin's ssh calls share one connection" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  grep -q "^ssh .*-o ControlMaster=auto .*-o ControlPersist=60 .*$host true$" "$FAKE_LOG"
}

@test "new: lists Beams once and does not list again after creating" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  [ "$(call_count 'beams ls -f json')" -eq 1 ]
  run jq -r '.[].id' "$HERDR_PLUGIN_STATE_DIR/beams.json"
  [[ "$output" == *"new-beam"* ]]
}

@test "new: records the profile with the Beam's uuid host" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  run jq -r '.[] | select(.label == "new-beam") | .target' "$FAKE_STATE/machines.json"
  [ "$output" = "ssh://$host" ]
}

@test "new: drops an expired Beam's profile on entry, while the Beam is being created" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"creating a Beam on example.beams.sh"*"gone-beam is gone"*"Beam new-beam created"* ]]
  grep -q "herdr machine remove id-gone-beam" "$FAKE_LOG"
  calls_in_order "herdr machine remove id-gone-beam" "herdr machine add"
}

@test "new: says what it is waiting for during the two long silences" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Beam new-beam created"*"◐ waiting for the Beam to accept SSH"*"SSH up"*"◐ starting herdr's server on the Beam"*"new-beam is in the sidebar"* ]]
}

@test "new: honours BEAM_LOGIN and BEAM_AGENT_KIND from the env file" {
  printf 'BEAMS_PROXY=example.beams.sh\nBEAM_LOGIN=dev\nBEAM_AGENT_KIND=codex\n' > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  grep -q "^herdr machine add ssh://dev@cccccccc-0000-4000-8000-000000000003.example.beams.sh --label new-beam$" "$FAKE_LOG"
  grep -q "integration install codex" "$FAKE_LOG"
}

@test "new: does not ask to start an agent without a terminal" {
  run_script beam-new.sh
  [ "$status" -eq 0 ]
  [[ "$output" != *"Start a"* ]]
  ! grep -q "agent start" "$FAKE_LOG"
}

@test "new: fails before touching anything when not logged in" {
  touch "$FAKE_STATE/not-logged-in"
  run_script beam-new.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"tsh login --proxy=example.beams.sh"* ]]
  ! grep -q "^ssh" "$FAKE_LOG"
  ! grep -q "^herdr" "$FAKE_LOG"
}

@test "new: gives up when the Beam never accepts SSH" {
  echo 99 > "$FAKE_STATE/ssh-fail-count"
  run_script beam-new.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not accept SSH"* ]]
  ! grep -q "machine add" "$FAKE_LOG"
}

@test "new: refuses to run without BEAMS_PROXY" {
  : > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-new.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"set BEAMS_PROXY="* ]]
  [ ! -s "$FAKE_LOG" ]
}
