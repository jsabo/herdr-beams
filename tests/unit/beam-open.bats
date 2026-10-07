#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

@test "open: an action opens the pane of the same id through the running herdr, with its question answered" {
  run_script beam-open.sh status
  [ "$status" -eq 0 ]
  grep -qx "herdr plugin pane open --plugin herdr-beams --entrypoint status --env BEAMS_YES=1" "$FAKE_LOG"
}

@test "open: refuses a pane id the manifest does not declare" {
  run_script beam-open.sh nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pane named nope"* ]]
  ! grep -q "plugin pane open" "$FAKE_LOG"
}

@test "open: needs no terminal and never asks anything" {
  run_script beam-open.sh new
  [ "$status" -eq 0 ]
  [[ "$output" != *"press any key"* ]]
}
