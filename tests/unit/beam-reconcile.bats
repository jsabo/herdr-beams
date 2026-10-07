#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

@test "reconcile: lists Beams and machines once each, plus one refresh after a removal" {
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [ "$(call_count 'beams ls -f json')" -eq 1 ]
  [ "$(call_count 'herdr machine list --json')" -le 3 ]
}

@test "reconcile: removes the profile of a Beam that no longer exists" {
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone-beam is gone"* ]]
  grep -q "^herdr machine remove id-gone-beam$" "$FAKE_LOG"
  run jq -r '.[].label' "$FAKE_STATE/machines.json"
  [[ "$output" != *"gone-beam"* ]]
}

@test "reconcile: leaves machines that are not Beams alone" {
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  ! grep -q "machine remove id-workbox" "$FAKE_LOG"
  run jq -r '.[].label' "$FAKE_STATE/machines.json"
  [[ "$output" == *"workbox"* ]]
}

@test "reconcile: adds a profile for a Beam that has none" {
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"added profile for beta-two"* ]]
  grep -q "^herdr machine add ssh://beams@bbbbbbbb-0000-4000-8000-000000000002.example.beams.sh --label beam/beta-two$" "$FAKE_LOG"
  ! grep -q "machine add .*alpha-one" "$FAKE_LOG"
}

@test "reconcile: relabels a profile from an older version as beam/<id>, once" {
  jq 'map(if .id == "id-alpha-one" then .label = "alpha-one" else . end)' \
    "$FAKE_STATE/machines.json" > "$FAKE_STATE/m.tmp" && mv "$FAKE_STATE/m.tmp" "$FAKE_STATE/machines.json"
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"relabelled alpha-one as beam/alpha-one"* ]]
  grep -q "^herdr machine rename id-alpha-one --label beam/alpha-one$" "$FAKE_LOG"
  [ "$(call_count 'machine rename')" -eq 1 ]
  ! grep -q "machine add .*alpha-one" "$FAKE_LOG"
  run jq -r '.[] | select(.id == "id-alpha-one") | .label' "$FAKE_STATE/machines.json"
  [ "$output" = "beam/alpha-one" ]
  : > "$FAKE_LOG"
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  ! grep -q "machine rename" "$FAKE_LOG"
}

@test "reconcile: never renames a profile that is already right, or one that is not a Beam" {
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  ! grep -q "machine rename" "$FAKE_LOG"
  run jq -r '.[] | select(.id == "id-workbox") | .label' "$FAKE_STATE/machines.json"
  [ "$output" = "workbox" ]
}

@test "reconcile: BEAM_LABEL_PREFIX in the settings file changes the label form" {
  printf 'BEAMS_PROXY=example.beams.sh\nBEAM_LABEL_PREFIX=\n' > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  grep -q "^herdr machine rename id-alpha-one --label alpha-one$" "$FAKE_LOG"
  grep -q "^herdr machine add ssh://beams@bbbbbbbb-0000-4000-8000-000000000002.example.beams.sh --label beta-two$" "$FAKE_LOG"
}

@test "reconcile: reports a Beam without herdr instead of failing" {
  touch "$FAKE_STATE/machine-add-fails"
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"beta-two has no herdr yet"* ]]
}

@test "reconcile: refreshes the state file" {
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  run jq -r '.[].id' "$HERDR_PLUGIN_STATE_DIR/beams.json"
  [ "${lines[0]}" = "alpha-one" ]
  [ "${lines[1]}" = "beta-two" ]
}

@test "reconcile: exits 0 and does nothing when not logged in" {
  touch "$FAKE_STATE/not-logged-in"
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"not logged in"* ]]
  ! grep -q "^herdr" "$FAKE_LOG"
}

@test "reconcile: exits 0 and does nothing when BEAMS_PROXY is unset" {
  : > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEAMS_PROXY not set"* ]]
  [ ! -s "$FAKE_LOG" ]
}
