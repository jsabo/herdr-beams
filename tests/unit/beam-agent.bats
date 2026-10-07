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
    "herdr --machine alpha-one workspace create --cwd ~ --label api --no-focus" \
    "herdr --machine alpha-one agent start claude --kind claude --pane w9:p1 -- --dangerously-skip-permissions" \
    "herdr --machine alpha-one agent prompt claude Read SPEC.md and start."
  # the name check runs alongside the workspace create, so only its presence is fixed
  [ "$(call_count 'herdr --machine alpha-one agent list')" -eq 1 ]
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
  grep -q "^herdr --machine alpha-one workspace create --cwd ~ --label My API Server! --no-focus$" "$FAKE_LOG"
}

@test "agent: prints how to watch the agent before the slow parts" {
  run_script beam-agent.sh alpha-one api
  [ "$status" -eq 0 ]
  calls_in_order "workspace create" "agent start"
  [[ "$output" == *"watch it:   herdr --machine alpha-one agent read claude"* ]]
}

@test "agent: a prompt with several words is passed as one argument" {
  run_script beam-agent.sh alpha-one api fix the failing test
  [ "$status" -eq 0 ]
  grep -q "^herdr --machine alpha-one agent prompt claude fix the failing test$" "$FAKE_LOG"
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
  grep -q "^herdr --machine alpha-one agent list$" "$FAKE_LOG"
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
    "herdr --machine new-beam workspace create --cwd ~ --label work --no-focus" \
    "herdr --machine new-beam agent start claude"
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
