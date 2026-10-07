#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

host="beams@aaaaaaaa-0000-4000-8000-000000000001.example.beams.sh"

@test "services: lists beam-init services over ssh to the Beam's uuid host" {
  run_script beam-services.sh alpha-one
  [ "$status" -eq 0 ]
  [[ "$output" == *"beam-init services on alpha-one"* ]]
  [[ "$output" == *"web (running PID=597)"* ]]
  grep -q "^ssh .*-o ControlMaster=auto .*$host beamctl list$" "$FAKE_LOG"
  # without a service and without a terminal it stops after the list
  ! grep -q "beamctl logs" "$FAKE_LOG"
}

@test "services: at the keyboard, an empty answer closes without following logs" {
  run_interactive beam-services.sh alpha-one <<<$'\nx'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Follow logs of service (empty to close):"* ]]
  ! grep -q "beamctl logs" "$FAKE_LOG"
}

@test "services: follows one service's logs with a terminal-allocating ssh" {
  run_script beam-services.sh alpha-one web
  [ "$status" -eq 0 ]
  grep -q "^ssh .* -t $host beamctl logs --follow web$" "$FAKE_LOG"
  [[ "$output" == *"following: beamctl logs --follow web"* ]]
}

@test "services: quotes a hostile service name" {
  run_script beam-services.sh alpha-one 'web; rm -rf /'
  [ "$status" -eq 0 ]
  grep -q "beamctl logs --follow web\\\\;\\\\ rm\\\\ -rf\\\\ /" "$FAKE_LOG"
}

@test "services: fails for an unknown Beam before using ssh" {
  run_script beam-services.sh nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"* ]]
  ! grep -q "^ssh" "$FAKE_LOG"
}

@test "services: drops an expired Beam's profile on entry" {
  run_script beam-services.sh alpha-one
  calls_in_order "herdr machine remove id-gone-beam" "beamctl list"
}
