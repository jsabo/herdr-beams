#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

@test "agent: creates an unfocused workspace, starts claude in yolo mode in its root pane, sends the prompt" {
  run_script beam-agent.sh alpha-one api "Read SPEC.md and start."
  [ "$status" -eq 0 ]
  [[ "$output" == *"workspace api on alpha-one, pane w9:p1"* ]]
  [[ "$output" == *"claude is ready as agent claude"* ]]
  [[ "$output" == *"prompt sent"* ]]
  calls_in_order \
    "herdr --machine id-alpha-one workspace create --cwd ~ --label api --no-focus" \
    "herdr --machine id-alpha-one agent start claude --kind claude --pane w9:p1 -- --dangerously-skip-permissions" \
    "herdr --machine id-alpha-one agent prompt claude Read SPEC.md and start."
  # the name check runs alongside the workspace create, so only its presence is fixed
  [ "$(call_count 'herdr --machine id-alpha-one agent list')" -eq 1 ]
  calls_in_order "agent list" "agent start"
}

@test "agent: never takes over the Beam's default workspace, which must keep focus so done is not cleared" {
  run_script beam-agent.sh alpha-one api
  [ "$status" -eq 0 ]
  ! grep -q "workspace rename" "$FAKE_LOG"
  ! grep -q "workspace focus" "$FAKE_LOG"
  ! grep -q "pane w1:p1" "$FAKE_LOG"
  grep -q -- "--no-focus" "$FAKE_LOG"
}

@test "agent: names the agent after its kind, with a counter when taken" {
  printf 'claude\nclaude-2\n' > "$FAKE_STATE/agent-names"
  run_script beam-agent.sh alpha-one review
  [ "$status" -eq 0 ]
  grep -q "agent start claude-3 --kind claude" "$FAKE_LOG"
  [[ "$output" == *"agent read claude-3"* ]]
}

@test "agent: the workspace label is used as given" {
  run_script beam-agent.sh alpha-one "My API Server!"
  [ "$status" -eq 0 ]
  grep -q "^herdr --machine id-alpha-one workspace create --cwd ~ --label My API Server! --no-focus$" "$FAKE_LOG"
}

@test "agent: prints how to watch the agent before the slow parts" {
  run_script beam-agent.sh alpha-one api
  [ "$status" -eq 0 ]
  calls_in_order "workspace create" "agent start"
  [[ "$output" == *"watch it:   herdr --machine id-alpha-one agent read claude"* ]]
}

@test "agent: a prompt with several words is passed as one argument" {
  run_script beam-agent.sh alpha-one api fix the failing test
  [ "$status" -eq 0 ]
  grep -q "^herdr --machine id-alpha-one agent prompt claude fix the failing test$" "$FAKE_LOG"
}

@test "agent: without a prompt and without a terminal it only starts the agent" {
  run_script beam-agent.sh alpha-one api
  [ "$status" -eq 0 ]
  [[ "$output" != *"prompt sent"* ]]
  ! grep -q "agent prompt" "$FAKE_LOG"
  ! grep -q "agent wait" "$FAKE_LOG"
}

@test "agent: never waits on the agent, with or without a terminal; the sidebar shows its state" {
  run_script beam-agent.sh alpha-one api "do it"
  [ "$status" -eq 0 ]
  ! grep -q "agent wait" "$FAKE_LOG"
  ! grep -q "agent read" "$FAKE_LOG"
  run_interactive beam-agent.sh alpha-one api "do it" <<<$'x'
  [ "$status" -eq 0 ]
  [[ "$output" != *"wait here"* ]]
  [[ "$output" == *"◐ working · pane w9:p1"*"press any key to close"* ]]
  ! grep -q "agent wait" "$FAKE_LOG"
}

@test "agent: BEAM_AGENT_KIND and BEAM_AGENT_ARGS override the defaults, and the name follows the kind" {
  printf 'BEAMS_PROXY=example.beams.sh\nBEAM_AGENT_KIND=codex\nBEAM_AGENT_ARGS="--full-auto --model o4"\n' > "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-agent.sh alpha-one api
  [ "$status" -eq 0 ]
  grep -q "agent start codex --kind codex --pane w9:p1 -- --full-auto --model o4$" "$FAKE_LOG"
}

@test "agent: uses the selected machine when no Beam id is given" {
  select_machine alpha-one
  run_script beam-agent.sh "" api
  [ "$status" -eq 0 ]
  grep -q "^herdr --machine id-alpha-one agent list$" "$FAKE_LOG"
}

@test "agent: refuses to guess the Beam without a terminal" {
  run_script beam-agent.sh "" api
  [ "$status" -eq 1 ]
  [[ "$output" == *"several Beams"* ]]
}

@test "agent: rejects an unknown Beam id before talking to its herdr" {
  run_script beam-agent.sh nope api
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"* ]]
  ! grep -q "^herdr --machine" "$FAKE_LOG"
}

@test "agent: with no Beams and nobody at the keyboard, it fails and says why" {
  printf '[]' > "$FAKE_STATE/beams.json"
  run_script beam-agent.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beams; create one with the New Beam pane"* ]]
  ! grep -q "beams add" "$FAKE_LOG"
}

@test "agent: with no Beams and someone at the keyboard, offers to create one, then starts the agent in it with no second question" {
  printf '[]' > "$FAKE_STATE/beams.json"
  # y: create it; then the label and the prompt, both default
  run_interactive beam-agent.sh <<<$'y\n\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Beams yet. Create one and start the agent in it? [Y/n]"* ]]
  [[ "$output" == *"new-beam is in the sidebar"* ]]
  [[ "$output" != *"Start a claude agent in it now?"* ]]
  [[ "$output" == *"Workspace label [work]:"* ]]
  calls_in_order "beams add --no-console -f json" "herdr machine add" \
    "herdr --machine id-new-beam workspace create --cwd ~ --label work --no-focus" \
    "herdr --machine id-new-beam agent start claude"
}

@test "agent: from a keybinding with no Beams, creates one and starts the agent without any y/N" {
  printf '[]' > "$FAKE_STATE/beams.json"
  # only the label and the prompt are asked
  run_bound beam-agent.sh <<<$'api\nfix it\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Y/n]"* ]]
  [[ "$output" != *"[y/N]"* ]]
  [[ "$output" == *"no Beams on example.beams.sh"* ]]
  calls_in_order "beams add --no-console -f json" "herdr machine add" \
    "workspace create --cwd ~ --label api --no-focus" \
    "agent prompt claude fix it"
}

@test "agent: declining the offer to create a Beam is a visible failure" {
  printf '[]' > "$FAKE_STATE/beams.json"
  run_interactive beam-agent.sh <<<$'n\nx'
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beams"*"failed (exit 1)"*"press any key"* ]]
  ! grep -q "beams add" "$FAKE_LOG"
}

@test "agent: at the keyboard, asks for the label and the prompt and accepts the defaults" {
  run_interactive beam-agent.sh alpha-one <<<$'\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Workspace label [work]:"*"First prompt (empty for none):"* ]]
  grep -q -- "--label work --no-focus" "$FAKE_LOG"
  ! grep -q "agent prompt" "$FAKE_LOG"
}

@test "agent: drops an expired Beam's profile on entry" {
  run_script beam-agent.sh alpha-one api
  calls_in_order "herdr machine remove id-gone-beam" "agent start"
}

@test "agent: resolves renamed profiles and changed prefixes using the Beam UUID" {
  jq 'map(if .id == "id-alpha-one" then .label = "custom-name" else . end)' \
    "$FAKE_STATE/machines.json" > "$FAKE_STATE/renamed.json"
  mv "$FAKE_STATE/renamed.json" "$FAKE_STATE/machines.json"
  printf 'BEAM_LABEL_PREFIX=changed/\n' >> "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-agent.sh alpha-one review
  [ "$status" -eq 0 ]
  grep -q '^herdr --machine id-alpha-one agent start claude' "$FAKE_LOG"
  ! grep -q -- '--machine changed/alpha-one' "$FAKE_LOG"
}

@test "agent: missing sidebar profile fails before integration or workspace creation" {
  run_script beam-agent.sh beta-two review
  [ "$status" -ne 0 ]
  [[ "$output" == *'has no sidebar entry'*'beam-reconcile.sh'* ]]
  ! grep -q '^ssh\|workspace create' "$FAKE_LOG"
}

@test "agent: existing Beam launches still install the selected integration each time" {
  run_script beam-agent.sh --profile claude-opus alpha-one
  [ "$status" -eq 0 ]
  run_script beam-agent.sh --profile codex-sol alpha-one
  [ "$status" -eq 0 ]
  [ "$(call_count 'integration install claude')" -eq 1 ]
  [ "$(call_count 'integration install codex')" -eq 1 ]
}

@test "fake herdr: rejects an unknown machine selector" {
  run "$HERDR_BIN_PATH" --machine missing-machine agent list
  [ "$status" -ne 0 ]
  [[ "$output" == *'unknown machine missing-machine'* ]]
}

@test "agent: invalid workspace responses never start an agent and clean temporary files" {
  export TMPDIR="$BATS_TEST_TMPDIR/launch-temp"
  mkdir -p "$TMPDIR"
  for response in '{}' 'null' '[]' '{' '{"result":{"root_pane":{"pane_id":null}}}' \
      '{"result":{"root_pane":{"pane_id":""}}}' '{"result":{"root_pane":{"pane_id":7}}}'; do
    printf '%s' "$response" > "$FAKE_STATE/workspace-response.json"
    : > "$FAKE_LOG"
    run_script beam-agent.sh alpha-one review
    [ "$status" -ne 0 ]
    [[ "$output" == *'returned no valid pane ID'* ]]
    ! grep -q 'agent start' "$FAKE_LOG"
    [ -z "$(ls -A "$TMPDIR")" ]
  done
}

@test "agent: malformed agent lists fail with the created workspace's recovery context" {
  for response in '{}' '{"result":{"agents":null}}' '{"result":{"agents":[{}]}}' \
      '{"result":{"agents":[{"name":7}]}}'; do
    printf '%s' "$response" > "$FAKE_STATE/agent-list-response.json"
    : > "$FAKE_LOG"
    run_script beam-agent.sh alpha-one review
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid agent list'*'pane w9:p1'* ]]
    ! grep -q 'agent start' "$FAKE_LOG"
  done
}

@test "agent: failed agent listing cleans its temporary file" {
  export TMPDIR="$BATS_TEST_TMPDIR/launch-temp"
  mkdir -p "$TMPDIR"
  touch "$FAKE_STATE/agent-list-fails"
  run_script beam-agent.sh alpha-one review
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not list the agents'* ]]
  [ -z "$(ls -A "$TMPDIR")" ]
  ! grep -q 'agent start' "$FAKE_LOG"
}

# ---- on the Beam itself ----------------------------------------------------
#
# What a keybinding pressed while that Beam is selected does: the Beam's own
# herdr publishes the key and runs the script, so there is no Beam to pick, no
# --machine forwarding and no SSH.

@test "agent, in a Beam: starts the agent through the Beam's own herdr, with no --machine and no ssh" {
  run_in_beam beam-agent.sh api "Read SPEC.md and start." </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"workspace api on alpha-one, pane w9:p1"* ]]
  [[ "$output" == *"claude is ready as agent claude"* ]]
  calls_in_order \
    "herdr integration install claude" \
    "herdr workspace create --cwd ~ --label api --no-focus" \
    "herdr agent start claude --kind claude --pane w9:p1 -- --dangerously-skip-permissions" \
    "herdr agent prompt claude Read SPEC.md and start."
  ! grep -q "^herdr --machine" "$FAKE_LOG"
  ! grep -q "^ssh" "$FAKE_LOG"
  ! grep -q "beams ls" "$FAKE_LOG"
}

@test "agent, in a Beam: the workspace still has no focus, so done survives" {
  run_in_beam beam-agent.sh api </dev/null
  [ "$status" -eq 0 ]
  grep -q "^herdr workspace create --cwd ~ --label api --no-focus$" "$FAKE_LOG"
}

@test "agent, in a Beam: the first argument is the workspace label, not a Beam id" {
  run_in_beam beam-agent.sh </dev/null
  [ "$status" -eq 0 ]
  grep -q -- "--label work --no-focus" "$FAKE_LOG"
  [[ "$output" == *"workspace work on alpha-one"* ]]
}

@test "agent, in a Beam: the card tells you to drive it without --machine" {
  run_in_beam beam-agent.sh api </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"watch it:   herdr agent read claude"* ]]
  [[ "$output" != *"herdr --machine"* ]]
}

@test "agent, in a Beam: a profile still decides the harness and its arguments" {
  run_in_beam beam-agent.sh --profile claude-opus api </dev/null
  [ "$status" -eq 0 ]
  grep -q "^herdr agent start claude --kind claude --pane w9:p1 -- --model " "$FAKE_LOG"
}
