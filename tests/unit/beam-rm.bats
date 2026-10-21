#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

@test "rm: removes the Beam first, then the herdr profile" {
  run_script beam-rm.sh alpha-one
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed alpha-one"* ]]
  calls_in_order "tsh --proxy=example.beams.sh beams rm alpha-one" "herdr machine remove id-alpha-one"
  run jq -r '.[].id' "$FAKE_STATE/beams.json"
  [[ "$output" != *"alpha-one"* ]]
}

@test "rm: a Beam without a profile is just deleted" {
  run_script beam-rm.sh beta-two
  [ "$status" -eq 0 ]
  ! grep -q "machine remove id-beta-two" "$FAKE_LOG"
  grep -q "beams rm beta-two$" "$FAKE_LOG"
}

@test "rm: does not ask for confirmation without a terminal" {
  run_script beam-rm.sh alpha-one
  [ "$status" -eq 0 ]
  [[ "$output" != *"[y/N]"* ]]
}

@test "rm: at the keyboard, anything but y keeps the Beam" {
  run_interactive beam-rm.sh alpha-one <<<$'\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Delete Beam alpha-one and everything in it? [y/N]"* ]]
  ! grep -q "beams rm" "$FAKE_LOG"
  ! grep -q "machine remove id-alpha-one" "$FAKE_LOG"
}

@test "rm: at the keyboard, y deletes" {
  run_interactive beam-rm.sh alpha-one <<<$'y\nx'
  [ "$status" -eq 0 ]
  calls_in_order "beams rm alpha-one" "herdr machine remove id-alpha-one"
}

@test "rm: BEAMS_YES=0 in the settings file brings the question back for a keybinding" {
  printf 'BEAMS_PROXY=example.beams.sh\nBEAMS_YES=0\n' > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_bound beam-rm.sh alpha-one <<<$'\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Delete Beam alpha-one and everything in it? [y/N]"* ]]
  ! grep -q "beams rm" "$FAKE_LOG"
}

@test "rm: from a keybinding, deletes without asking" {
  run_bound beam-rm.sh alpha-one <<<$'x'
  [ "$status" -eq 0 ]
  [[ "$output" != *"[y/N]"* ]]
  [[ "$output" == *"removed alpha-one"* ]]
  calls_in_order "beams rm alpha-one" "herdr machine remove id-alpha-one"
}

@test "rm: rejects an unknown Beam before calling tsh" {
  run_script beam-rm.sh nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"* ]]
  ! grep -q "beams rm" "$FAKE_LOG"
  # the only removal is the expired Beam every pane drops on entry
  [ "$(call_count 'machine remove')" -eq 1 ]
  grep -q "machine remove id-gone-beam" "$FAKE_LOG"
}

@test "rm: refreshes the state file from the cache, without another tsh ls" {
  run_script beam-rm.sh alpha-one
  run jq -r '.[].id' "$HERDR_PLUGIN_STATE_DIR/beams.json"
  [ "$output" = "beta-two" ]
  [ "$(call_count 'beams ls -f json')" -eq 1 ]
}

@test "rm: drops an expired Beam's profile on entry" {
  run_script beam-rm.sh alpha-one
  calls_in_order "herdr machine remove id-gone-beam" "herdr machine remove id-alpha-one"
}

@test "rm: deletion failure preserves the live Beam and sidebar profile" {
  touch "$FAKE_STATE/rm-fails"
  run_script beam-rm.sh alpha-one
  [ "$status" -ne 0 ]
  jq -e 'any(.id == "alpha-one")' "$FAKE_STATE/beams.json"
  jq -e 'any(.id == "id-alpha-one")' "$FAKE_STATE/machines.json"
  ! grep -q 'machine remove id-alpha-one' "$FAKE_LOG"
  [[ "$output" == *'simulated deletion failure'*'sidebar entry was retained'* ]]
}

@test "rm: successful deletion is saved even if profile cleanup fails" {
  # Avoid a failure during the expired-profile reconciliation on entry.
  jq 'map(select(.id != "id-gone-beam"))' "$FAKE_STATE/machines.json" > "$FAKE_STATE/m.tmp"
  mv "$FAKE_STATE/m.tmp" "$FAKE_STATE/machines.json"
  touch "$FAKE_STATE/machine-remove-fails"
  run_script beam-rm.sh alpha-one
  [ "$status" -ne 0 ]
  jq -e 'all(.id != "alpha-one")' "$FAKE_STATE/beams.json"
  jq -e 'all(.id != "alpha-one")' "$HERDR_PLUGIN_STATE_DIR/beams.json"
  [[ "$output" == *'was deleted but profile id-alpha-one remains'* ]]
}
