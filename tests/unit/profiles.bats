#!/usr/bin/env bats
load '../helpers'
setup() { setup_fakes; }

profile_args() {
  run bash -c '. bin/common.sh; load_agent_profile "$1"; printf "%s\n" "$AGENT_KIND"; printf "<%s>\n" "${AGENT_ARGS[@]}"' _ "$1"
}

@test "profiles: bundled Claude and Codex fields map to harness arguments" {
  profile_args claude-opus
  [ "$status" -eq 0 ]
  [ "$output" = $'claude\n<--model>\n<claude-opus-5>\n<--effort>\n<high>\n<--dangerously-skip-permissions>' ]
  profile_args codex-sol
  [ "$status" -eq 0 ]
  [ "$output" = $'codex\n<--model>\n<gpt-5.6-sol>\n<-c>\n<model_reasoning_effort="high">\n<--sandbox>\n<workspace-write>\n<--ask-for-approval>\n<never>' ]
  profile_args claude-sonnet
  [ "$status" -eq 0 ]
  [[ "$output" == *'<claude-sonnet-5>'*'<medium>'* ]]
  profile_args codex-terra
  [ "$status" -eq 0 ]
  [[ "$output" == *'<gpt-5.6-terra>'*'<on-request>'* ]]
}

@test "profiles: user records replace defaults, add profiles and preserve literal model strings" {
  cat > "$HERDR_PLUGIN_CONFIG_DIR/profiles.json" <<'JSON'
{"claude-opus":{"harness":"claude","model":"proxy alias $(touch /tmp/profile-injection) ; * 'quoted'","effort":"low","approval":"default"},
 "review":{"harness":"codex","model":"proxy-review","effort":"xhigh","approval":"default","sandbox":"read-only"}}
JSON
  profile_args claude-opus
  [ "$status" -eq 0 ]
  [ "${lines[2]}" = "<proxy alias \$(touch /tmp/profile-injection) ; * 'quoted'>" ]
  [[ "$output" != *'dangerously'* ]]
  profile_args review
  [ "$status" -eq 0 ]
  [[ "$output" == *'<read-only>'* ]]
  [[ "$output" != *'--ask-for-approval'* ]]
}

@test "profiles: reject malformed records, invalid fields and unknown names before launching" {
  for json in '[]' '{' 'null' '{"bad":{}}' \
    '{"bad":{"harness":"shell","model":"m","effort":"high","approval":"bypass"}}' \
    '{"bad":{"harness":"claude","model":"m","effort":"xhigh","approval":"bypass"}}' \
    '{"bad":{"harness":"claude","model":"m","effort":"high","approval":"never"}}' \
    '{"bad":{"harness":"claude","model":"m","effort":"high","approval":"default","extra":true}}' \
    '{"bad":{"harness":"codex","model":"m","effort":"high","approval":"never","sandbox":"oops"}}' \
    '{"bad":{"harness":"claude","model":"a\u0000b","effort":"high","approval":"bypass"}}'; do
    printf '%s' "$json" > "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
    run_script beam-agent.sh --profile bad alpha-one
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid profiles'* ]]
    [ ! -s "$FAKE_LOG" ]
  done
  rm "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
  run_script beam-agent.sh --profile missing alpha-one
  [ "$status" -ne 0 ]
  [[ "$output" == *'no agent profile named missing'* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "profiles: explicit profile overrides env legacy settings without combining flags" {
  printf 'BEAM_AGENT_KIND=codex\nBEAM_AGENT_ARGS="--full-auto"\n' >> "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-agent.sh --profile claude-sonnet alpha-one review
  [ "$status" -eq 0 ]
  grep -q 'agent start claude --kind claude .*--model claude-sonnet-5 --effort medium --dangerously-skip-permissions$' "$FAKE_LOG"
  ! grep -q -- '--full-auto' "$FAKE_LOG"
}

@test "profiles: picker selects a profile before workspace questions and launch" {
  run_interactive beam-profiles.sh alpha-one <<<$'3\nreview\ncheck it\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'claude-opus · claude · claude-opus-5'*'Profile:'*'Workspace label'* ]]
  calls_in_order 'integration install codex' 'workspace create --cwd ~ --label review --no-focus' 'agent start codex' 'agent prompt codex check it'
}

@test "profiles: picker cancels empty, invalid, out of range and EOF input without launching" {
  for choice in '' 0 5 nope 999999999999999999999999; do
    run_interactive beam-profiles.sh alpha-one <<<"$choice"
    [ "$status" -ne 0 ]
    [[ "$output" == *'no agent profile chosen'* ]]
    [ ! -s "$FAKE_LOG" ]
  done
  run_interactive beam-profiles.sh alpha-one </dev/null
  [ "$status" -ne 0 ]
  run_script beam-profiles.sh alpha-one
  [ "$status" -ne 0 ]
  [[ "$output" == *'needs a terminal'* ]]
}

@test "profiles: chosen profile and launch arguments survive Beam creation" {
  printf '[]' > "$FAKE_STATE/beams.json"
  run_bound beam-agent.sh --profile codex-terra '' 'review space' 'read SPEC.md' </dev/null
  [ "$status" -eq 0 ]
  calls_in_order 'beams add' 'integration install codex' 'machine add' \
    'workspace create --cwd ~ --label review space --no-focus' \
    'agent start codex --kind codex --pane w9:p1 -- --model gpt-5.6-terra' \
    'agent prompt codex read SPEC.md'
  [ "$(call_count 'beams add')" -eq 1 ]
}

@test "profiles: picker selection survives creation without a second picker" {
  printf '[]' > "$FAKE_STATE/beams.json"
  run_bound beam-profiles.sh <<<$'4\napi\nfix it\n'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -o 'Profile:' | wc -l)" -eq 1 ]
  grep -q 'agent start codex .*--model gpt-5.6-terra' "$FAKE_LOG"
}

@test "profiles: direct actions open matching popups and use configurable profiles" {
  for pane in claude codex profiles; do
    run_script beam-open.sh "$pane"
    [ "$status" -eq 0 ]
    grep -q -- "--entrypoint $pane --env BEAMS_YES=1" "$FAKE_LOG"
  done
  run_script beam-claude.sh alpha-one
  [ "$status" -eq 0 ]
  grep -q 'agent start claude .*--model claude-opus-5' "$FAKE_LOG"
  printf 'BEAM_CODEX_PROFILE=codex-terra\n' >> "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-codex.sh alpha-one
  [ "$status" -eq 0 ]
  grep -q 'agent start codex .*--model gpt-5.6-terra' "$FAKE_LOG"
}

@test "profiles: two harnesses coexist on one Beam in separate workspace launches" {
  run_script beam-agent.sh --profile claude-opus alpha-one implementation
  [ "$status" -eq 0 ]
  printf 'claude\ncodex\n' > "$FAKE_STATE/agent-names"
  run_script beam-agent.sh --profile codex-sol alpha-one review
  [ "$status" -eq 0 ]
  calls_in_order 'integration install claude' 'workspace create --cwd ~ --label implementation --no-focus' \
    'agent start claude --kind claude' 'integration install codex' \
    'workspace create --cwd ~ --label review --no-focus' 'agent start codex-2 --kind codex'
  ! grep -q 'agent stop\|workspace focus\|worktree' "$FAKE_LOG"
}

@test "profiles: integration failure prevents workspace creation and agent start" {
  touch "$FAKE_STATE/integration-fails"
  run_script beam-agent.sh --profile codex-sol alpha-one
  [ "$status" -ne 0 ]
  ! grep -q 'workspace create\|agent start' "$FAKE_LOG"
}

@test "profiles: environment default is used but explicit profile wins" {
  printf 'BEAM_AGENT_PROFILE=codex-sol\n' >> "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-agent.sh alpha-one
  [ "$status" -eq 0 ]
  grep -q 'agent start codex .*--model gpt-5.6-sol' "$FAKE_LOG"
  run_script beam-agent.sh --profile claude-opus alpha-one
  [ "$status" -eq 0 ]
  grep -q 'agent start claude .*--model claude-opus-5' "$FAKE_LOG"
}

@test "profiles: explicit selection survives creation even with an env-file default" {
  printf 'BEAM_AGENT_PROFILE=claude-opus\n' >> "$HERDR_PLUGIN_CONFIG_DIR/env"
  printf '[]' > "$FAKE_STATE/beams.json"
  run_bound beam-agent.sh --profile codex-sol '' api 'fix it' </dev/null
  [ "$status" -eq 0 ]
  grep -q 'integration install codex' "$FAKE_LOG"
  grep -q 'agent start codex .*--model gpt-5.6-sol' "$FAKE_LOG"
  ! grep -q 'integration install claude' "$FAKE_LOG"
}

@test "profiles: launch preserves model argument boundaries without executing shell syntax" {
  model='proxy alias $(false); * "quoted"'
  jq -n --arg model "$model" '{literal:{harness:"claude",model:$model,effort:"high",approval:"default"}}' > "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
  run_script beam-agent.sh --profile literal alpha-one api
  [ "$status" -eq 0 ]
  argv=()
  while IFS= read -r -d '' arg; do argv+=("$arg"); done < "$FAKE_STATE/last-agent-argv"
  [ "${#argv[@]}" -eq 12 ]
  [ "${argv[8]}" = '--model' ]
  [ "${argv[9]}" = "$model" ]
  [ "${argv[10]}" = '--effort' ]
  [ "${argv[11]}" = high ]
}

@test "profiles: legacy empty arguments keep permission prompts as documented" {
  printf 'BEAM_AGENT_ARGS=""\n' >> "$HERDR_PLUGIN_CONFIG_DIR/env"
  run_script beam-agent.sh alpha-one api
  [ "$status" -eq 0 ]
  grep -q 'agent start claude --kind claude --pane w9:p1 --$' "$FAKE_LOG"
}
