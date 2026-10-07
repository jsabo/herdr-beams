#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

@test "publish: http is the default and prints the URL" {
  run_script beam-publish.sh alpha-one
  [ "$status" -eq 0 ]
  grep -q "^tsh --proxy=example.beams.sh beams publish alpha-one$" "$FAKE_LOG"
  [[ "$output" == *"URL: https://alpha-one-1234.example.beams.sh"* ]]
}

@test "publish: tcp adds --tcp" {
  run_script beam-publish.sh alpha-one tcp
  [ "$status" -eq 0 ]
  grep -q "^tsh --proxy=example.beams.sh beams publish --tcp alpha-one$" "$FAKE_LOG"
}

@test "publish: rejects an unknown protocol before calling tsh" {
  run_script beam-publish.sh alpha-one udp
  [ "$status" -eq 1 ]
  [[ "$output" == *"http or tcp"* ]]
  ! grep -q "publish" "$FAKE_LOG"
}

@test "publish: drops an expired Beam's profile on entry" {
  run_script beam-publish.sh alpha-one
  calls_in_order "herdr machine remove id-gone-beam" "beams publish alpha-one"
}

@test "publish: rejects an unknown Beam before calling tsh" {
  run_script beam-publish.sh nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"* ]]
  ! grep -q "publish" "$FAKE_LOG"
}

@test "publish: at the keyboard, an empty answer means http" {
  run_interactive beam-publish.sh alpha-one <<<$'\nx'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Protocol on port 8080, http or tcp [http]:"* ]]
  grep -q "^tsh --proxy=example.beams.sh beams publish alpha-one$" "$FAKE_LOG"
}

@test "publish: uses the selected machine's Beam" {
  select_machine alpha-one
  run_script beam-publish.sh
  [ "$status" -eq 0 ]
  grep -q "beams publish alpha-one$" "$FAKE_LOG"
}
