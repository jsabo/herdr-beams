#!/usr/bin/env bats
load '../helpers'

setup() {
  setup_fakes
  printf '[]' > "$FAKE_STATE/beams.json"
  printf '[]' > "$FAKE_STATE/machines.json"
  printf 'web (running PID=597)\n' > "$FAKE_STATE/beamctl-list.txt"
}

run_demo() { run env DEMO_AUTO=1 "$@" bash demo/demo.sh </dev/null; }

@test "demo: runs end to end without pauses" {
  run_demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"1. Where we start"* ]]
  [[ "$output" == *"7. Tear it down"* ]]
  [[ "$output" =~ Done\ in\ [0-9]+\ s\. ]]
  # the Beam is removed by step 7 and not again by the exit handler
  [ "$(call_count 'beams rm')" -eq 1 ]
  [[ "$output" != *"tearing down"* ]]
}

@test "demo: runs without pauses when nobody is at the keyboard, even without DEMO_AUTO" {
  run bash demo/demo.sh </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"7. Tear it down"* ]]
  [[ "$output" != *"[enter]"* ]]
}

@test "demo: names its story at the top, for the app and for a custom task" {
  run_demo
  [[ "$output" == *"Story: an agent builds and publishes an app"* ]]
  [[ "$output" != *"Task:"* ]]
  run_demo DEMO_PROMPT=$'write a haiku\nabout sandboxes'
  [[ "$output" == *"Story: an agent runs your task as you"* ]]
  [[ "$output" == *"Task: write a haiku"* ]]
  [[ "$output" != *"about sandboxes"*"Task:"* ]]
}

@test "demo: the task story is numbered 1 to 5 with no gap" {
  run_demo DEMO_PROMPT="write a haiku"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4. Wait for the agent"*"5. Tear it down"* ]]
  [[ "$output" != *"6. "* ]]
  [[ "$output" != *"7. "* ]]
}

@test "demo: says what state the agent actually reached" {
  run_demo
  [[ "$output" == *"went working, then done"* ]]
  [[ "$output" != *"notification fired"* ]]
}

@test "demo: a failed publish fails the demo and tears the Beam down" {
  touch "$FAKE_STATE/publish-fails"
  run_demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"tearing down new-beam"* ]]
  grep -q "beams rm new-beam" "$FAKE_LOG"
  [[ "$output" != *"Only you can open"* ]]
}

@test "demo: shows the audience the commands, not the plumbing around them" {
  run_demo
  [[ "$output" != *"bash -c"* ]]
  [[ "$output" != *"tee "* ]]
  [[ "$output" == *'$ herdr --machine new-beam agent wait claude --timeout 600000'* ]]
  [[ "$output" == *'$ bash bin/beam-publish.sh new-beam http'* ]]
}

@test "demo: lists the tenant's Beams three times in all, the scripts it runs inherit its cache" {
  run_demo
  [ "$status" -eq 0 ]
  # on entry, in step 1 (shown to the audience), and after the new Beam;
  # BEAMS_JSON is exported, so beam-new, beam-agent, services, publish and rm reuse it
  [ "$(call_count 'beams ls -f json')" -eq 3 ]
}

@test "demo: takes its Beam from what beam-new reported, not from a list diff" {
  # a Beam someone else created meanwhile must not be mistaken for the demo's
  jq '. + [{id: "aaaa-other", uuid: "eeeeeeee-0000-4000-8000-000000000005", expires: "2030-01-03T00:00:00Z", region: "us-east-1"}]' \
    "$FAKE_STATE/beams.json" > "$FAKE_STATE/b.tmp" && mv "$FAKE_STATE/b.tmp" "$FAKE_STATE/beams.json"
  run_demo
  [ "$status" -eq 0 ]
  grep -q "agent start claude.*" "$FAKE_LOG"
  grep -q "^herdr --machine new-beam workspace create" "$FAKE_LOG"
  ! grep -q "machine aaaa-other" "$FAKE_LOG"
  grep -q "beams rm new-beam$" "$FAKE_LOG"
  ! grep -q "beams rm aaaa-other" "$FAKE_LOG"
}

@test "demo: every step reports how long it took" {
  run_demo
  [ "$status" -eq 0 ]
  # eight timed steps: 1, 2, 3, 4, 4b, 5, 5b, 6, 7
  [ "$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g' | grep -cE '^\[[0-9]+\.[0-9]s\]$')" -ge 8 ]
}

@test "demo: issues the real command sequence, in order" {
  run_demo
  [ "$status" -eq 0 ]
  host="beams@cccccccc-0000-4000-8000-000000000003.example.beams.sh"
  expected=(
    "tsh --proxy=example.beams.sh beams add --no-console -f json"
    "herdr machine add ssh://$host --label new-beam"
    "herdr --machine new-beam workspace create --cwd ~ --label flask-app --no-focus"
    "herdr --machine new-beam agent start claude --kind claude --pane w9:p1 -- --dangerously-skip-permissions"
    "herdr --machine new-beam agent prompt claude "
    "herdr --machine new-beam agent wait claude --until working --timeout 20000"
    "herdr --machine new-beam agent wait claude --timeout 600000"
    "herdr --machine new-beam agent read claude --lines 40"
    "$host beamctl list"
    "$host curl -s localhost:8080"
    "tsh --proxy=example.beams.sh beams publish new-beam"
    "herdr machine remove id-new-beam"
    "tsh --proxy=example.beams.sh beams rm new-beam"
  )
  last=0
  for want in "${expected[@]}"; do
    n="$(grep -n -F -- "$want" "$FAKE_LOG" | cut -d: -f1 | awk -v last="$last" '$1 > last' | head -1)"
    [ -n "$n" ] || { echo "missing or out of order: $want"; cat "$FAKE_LOG"; return 1; }
    last="$n"
  done
}

@test "demo: the agent gets the task and is told to use beamctl" {
  run_demo
  grep -q "agent prompt claude .*beamctl start --name web" "$FAKE_LOG"
  grep -q "agent prompt claude .*0.0.0.0:8080" "$FAKE_LOG"
}

@test "demo: DEMO_PROMPT replaces the task and skips the app steps" {
  run_demo DEMO_PROMPT="write a haiku"
  [ "$status" -eq 0 ]
  grep -q "^herdr --machine new-beam agent prompt claude write a haiku$" "$FAKE_LOG"
  grep -q -- "--label task --no-focus" "$FAKE_LOG"
  grep -q "agent read claude --lines 40" "$FAKE_LOG"
  ! grep -q "beamctl list" "$FAKE_LOG"
  ! grep -q "localhost:8080" "$FAKE_LOG"
  ! grep -q "beams publish" "$FAKE_LOG"
  [[ "$output" != *"The app is a beam-init service"* ]]
  [[ "$output" != *"Publish port 8080"* ]]
  [[ "$output" == *"app steps"*"skipped"* ]]
  [[ "$output" == *"5. Tear it down"* ]]
}

@test "demo: DEMO_WORKSPACE names the agent's workspace" {
  run_demo DEMO_WORKSPACE=inventory DEMO_PROMPT="write a haiku"
  [ "$status" -eq 0 ]
  grep -q "workspace create --cwd ~ --label inventory --no-focus" "$FAKE_LOG"
}

@test "demo: shows the published URL and never opens it in auto mode" {
  run_demo
  [[ "$output" == *"https://new-beam-1234.example.beams.sh"* ]]
}

@test "demo: DEMO_KEEP leaves the Beam and its profile" {
  run_demo DEMO_KEEP=1
  [ "$status" -eq 0 ]
  ! grep -q "beams rm" "$FAKE_LOG"
  ! grep -q "machine remove" "$FAKE_LOG"
  [[ "$output" == *"leaving new-beam running"* ]]
}

@test "demo: tears the Beam down when a step fails" {
  touch "$FAKE_STATE/machine-add-fails"
  run_demo
  [ "$status" -ne 0 ]
  grep -q "beams rm new-beam" "$FAKE_LOG"
  [[ "$output" == *"tearing down new-beam"* ]]
}

@test "demo: fails early without BEAMS_PROXY" {
  : > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"set BEAMS_PROXY="* ]]
  [ ! -s "$FAKE_LOG" ]
}
