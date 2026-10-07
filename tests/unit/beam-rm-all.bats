#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

@test "rm-all: removes every Beam, profile first, in list order" {
  run_script beam-rm-all.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed 2 Beam(s)"* ]]
  calls_in_order "herdr machine remove id-alpha-one" \
    "tsh --proxy=example.beams.sh beams rm alpha-one" \
    "tsh --proxy=example.beams.sh beams rm beta-two"
  # beta-two has no profile, so the only other removal is the expired Beam
  [ "$(call_count 'machine remove')" -eq 2 ]
  [ "$(jq 'length' "$FAKE_STATE/beams.json")" -eq 0 ]
}

@test "rm-all: writes an empty state file from the cache, without another tsh ls" {
  run_script beam-rm-all.sh
  [ "$(jq 'length' "$HERDR_PLUGIN_STATE_DIR/beams.json")" -eq 0 ]
  [ "$(call_count 'beams ls -f json')" -eq 1 ]
}

@test "rm-all: does not ask for confirmation without a terminal" {
  run_script beam-rm-all.sh
  [ "$status" -eq 0 ]
  [[ "$output" != *"[y/N]"* ]]
}

@test "rm-all: at the keyboard, lists the Beams and anything but y keeps them" {
  run_interactive beam-rm-all.sh <<<$'\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha-one (in the sidebar)"* ]]
  [[ "$output" == *"beta-two"* ]]
  [[ "$output" == *"Delete 2 Beam(s) and everything in them? [y/N]"* ]]
  ! grep -q "beams rm" "$FAKE_LOG"
  ! grep -q "machine remove id-alpha-one" "$FAKE_LOG"
}

@test "rm-all: at the keyboard, y deletes them all" {
  run_interactive beam-rm-all.sh <<<$'y\nx'
  [ "$status" -eq 0 ]
  calls_in_order "herdr machine remove id-alpha-one" "beams rm alpha-one" "beams rm beta-two"
}

@test "rm-all: BEAMS_YES=0 in the settings file brings the question back for a keybinding" {
  printf 'BEAMS_PROXY=example.beams.sh\nBEAMS_YES=0\n' > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_bound beam-rm-all.sh <<<$'\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Delete 2 Beam(s) and everything in them? [y/N]"* ]]
  ! grep -q "beams rm" "$FAKE_LOG"
}

@test "rm-all: from a keybinding, lists them and deletes without asking" {
  run_bound beam-rm-all.sh <<<$'x'
  [ "$status" -eq 0 ]
  [[ "$output" != *"[y/N]"* ]]
  [[ "$output" == *"alpha-one (in the sidebar)"*"removed 2 Beam(s)"* ]]
  calls_in_order "herdr machine remove id-alpha-one" "beams rm alpha-one" "beams rm beta-two"
}

@test "rm-all: with no Beams, says so and exits cleanly" {
  echo '[]' > "$FAKE_STATE/beams.json"
  run_script beam-rm-all.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Beams on example.beams.sh; nothing to remove"* ]]
  ! grep -q "beams rm" "$FAKE_LOG"
}

@test "rm-all: drops an expired Beam's profile on entry" {
  run_script beam-rm-all.sh
  calls_in_order "herdr machine remove id-gone-beam" "herdr machine remove id-alpha-one"
}
