#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

@test "status: a header, then one card per Beam with its sidebar entry, region, expiry and SSH address" {
  run_script beam-status.sh
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Teleport Beams · Beam status · example.beams.sh" ]]
  [[ "$output" == *"╭─ alpha-one"*"● in the sidebar · us-west-2"*"expires 2030-01-01 10:00 UTC · in "*"ssh beams@aaaaaaaa-0000-4000-8000-000000000001.example.beams.sh"*"╰─"* ]]
  [[ "$output" == *"╭─ beta-two"*"○ no sidebar entry · us-east-1"*"expires 2030-01-01 11:00 UTC"*"ssh beams@bbbbbbbb-0000-4000-8000-000000000002.example.beams.sh"* ]]
}

@test "status: costs one Beam listing and never probes a machine; reachability is the sidebar's dot" {
  run_script beam-status.sh
  [ "$status" -eq 0 ]
  [ "$(call_count 'beams ls -f json')" -eq 1 ]
  ! grep -q "machine status" "$FAKE_LOG"
  ! grep -q "^herdr --machine" "$FAKE_LOG"
  ! grep -q "^ssh" "$FAKE_LOG"
}

@test "status: drops an expired Beam's profile on entry" {
  run_script beam-status.sh
  [[ "$output" == *"gone-beam is gone"* ]]
  grep -q "machine remove id-gone-beam" "$FAKE_LOG"
}

@test "status: with no Beams it says so and points at the new action" {
  printf '[]' > "$FAKE_STATE/beams.json"
  printf '[]' > "$FAKE_STATE/machines.json"
  run_script beam-status.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"○ no Beams on example.beams.sh"*"herdr plugin action invoke herdr-beams.new"* ]]
  [[ "$output" != *"╭─"* ]]
}

@test "status: fails with the login hint when not logged in" {
  touch "$FAKE_STATE/not-logged-in"
  run_script beam-status.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"tsh login"* ]]
}
