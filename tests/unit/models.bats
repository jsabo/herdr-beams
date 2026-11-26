#!/usr/bin/env bats
# The tenant's model catalog: how it is read from `tsh apps ls`, cached, checked
# before a launch, and offered in the profile picker.
load '../helpers'
setup() { setup_fakes; }

catalog() { cat "$HERDR_PLUGIN_STATE_DIR/models.json"; }
apps_calls() { call_count 'apps ls -f json'; }

# Rewrite the fake tenant's openai app model list.
openai_models() {
  jq --argjson m "$1" 'map(if .metadata.name == "openai" then .spec.inference.models = $m else . end)' \
    "$FAKE_STATE/apps.json" > "$FAKE_STATE/apps.json.tmp" && mv "$FAKE_STATE/apps.json.tmp" "$FAKE_STATE/apps.json"
}

@test "models: one launch name per upstream model, by harness, from the inference apps only" {
  run bash -c '. bin/common.sh; models_from_apps < "$FAKE_STATE/apps.json"'
  [ "$status" -eq 0 ]
  [ "$(jq -c '.harnesses | keys' <<<"$output")" = '["claude","codex"]' ]
  [ "$(jq -c .harnesses.claude.choices <<<"$output")" = '["anthropic.claude-opus-5-5","anthropic.claude-sonnet-5"]' ]
  [ "$(jq -c .harnesses.codex.choices <<<"$output")" = \
    '["openai.gpt-6-luna","openai.gpt-6.1-sol","openai.gpt-6.1-terra","openai.gpt-6.2-sol","zai.glm-5"]' ]
  jq -e '.proxy == "example.beams.sh" and (.harnesses.codex.names | index("gpt-6.2-sol") != null)' <<<"$output"
}

@test "models: a short-only name is its own launch name; an empty list is open; a fallback is kept" {
  openai_models '[{"name":"house-model"}]'
  jq 'map(if .metadata.name == "anthropic" then .spec.inference |= (.models = [] | .fallback_model = "x") else . end)' \
    "$FAKE_STATE/apps.json" > "$FAKE_STATE/apps.json.tmp" && mv "$FAKE_STATE/apps.json.tmp" "$FAKE_STATE/apps.json"
  run bash -c '. bin/common.sh; models_from_apps < "$FAKE_STATE/apps.json"'
  [ "$status" -eq 0 ]
  [ "$(jq -c .harnesses.codex.choices <<<"$output")" = '["house-model"]' ]
  jq -e '.harnesses.claude.open and .harnesses.claude.fallback == "x"' <<<"$output"
}

@test "models: a bundled profile launches, caches the catalog, and the next launch reuses it" {
  run_script beam-agent.sh --profile codex-sol alpha-one review
  [ "$status" -eq 0 ]
  grep -q 'agent start codex .*--model openai.gpt-6.1-sol' "$FAKE_LOG"
  [ "$(catalog | jq -r .proxy)" = example.beams.sh ]
  [ "$(apps_calls)" -eq 1 ]
  run_script beam-agent.sh --profile claude-opus alpha-one implementation
  [ "$status" -eq 0 ]
  [ "$(apps_calls)" -eq 1 ]
}

@test "models: a model the tenant does not offer stops the launch before any workspace" {
  printf '%s' '{"old":{"harness":"codex","model":"openai.gpt-5.6-sol","effort":"high","approval":"default","sandbox":"read-only"}}' \
    > "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
  run_script beam-agent.sh --profile old alpha-one review
  [ "$status" -ne 0 ]
  [[ "$output" == *'openai.gpt-5.6-sol is not offered on example.beams.sh; codex models: openai.gpt-6-luna, openai.gpt-6.1-sol,'* ]]
  [[ "$output" == *'pass --model'* ]]
  ! grep -q 'integration install\|workspace create\|agent start' "$FAKE_LOG"
}

@test "models: names match the way the app matches them, ignoring case and both name forms" {
  for model in GPT-6.2-SOL gpt-6.2-sol openai.gpt-6.2-sol; do
    : > "$FAKE_LOG"
    run_script beam-agent.sh --profile codex-sol --model "$model" alpha-one review
    [ "$status" -eq 0 ]
    grep -q -- "--model $model -c" "$FAKE_LOG"
  done
}

@test "models: a model added since the cache was written is found by one fresh listing" {
  openai_models '[{"name":"openai.gpt-6.1-sol"}]'
  run_script beam-agent.sh --profile codex-sol alpha-one review
  [ "$status" -eq 0 ]
  cp "$REPO/tests/fixtures/apps.json" "$FAKE_STATE/apps.json"
  : > "$FAKE_LOG"
  run_script beam-agent.sh --profile codex-sol --model openai.gpt-6.2-sol alpha-one review
  [ "$status" -eq 0 ]
  [ "$(apps_calls)" -eq 1 ]
  grep -q 'agent start codex .*--model openai.gpt-6.2-sol' "$FAKE_LOG"
  catalog | jq -e '.harnesses.codex.choices | index("openai.gpt-6.2-sol") != null'
}

@test "models: a cache from another tenant is not trusted" {
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  printf '%s\n' '{"proxy":"other.beams.sh","harnesses":{"codex":{"open":true,"fallback":"","names":[],"choices":[]}}}' \
    > "$HERDR_PLUGIN_STATE_DIR/models.json"
  run_script beam-agent.sh --profile codex-sol --model not-a-model alpha-one review
  [ "$status" -ne 0 ]
  [[ "$output" == *'not-a-model is not offered on example.beams.sh'* ]]
  [ "$(apps_calls)" -eq 1 ]
}

@test "models: with no listing the launch goes ahead unchecked and says so" {
  touch "$FAKE_STATE/apps-fails"
  run_script beam-agent.sh --profile codex-sol --model anything-goes alpha-one review
  [ "$status" -eq 0 ]
  [[ "$output" == *'could not read the model list on example.beams.sh; launching anything-goes unchecked'* ]]
  grep -q 'agent start codex .*--model anything-goes' "$FAKE_LOG"
}

@test "models: an unlisted name on an app with a fallback launches with a warning" {
  jq 'map(if .metadata.name == "openai" then .spec.inference.fallback_model = "openai.gpt-6-luna" else . end)' \
    "$FAKE_STATE/apps.json" > "$FAKE_STATE/apps.json.tmp" && mv "$FAKE_STATE/apps.json.tmp" "$FAKE_STATE/apps.json"
  run_script beam-agent.sh --profile codex-sol --model gpt-9 alpha-one review
  [ "$status" -eq 0 ]
  [[ "$output" == *'example.beams.sh does not list gpt-9; it will serve openai.gpt-6-luna instead'* ]]
}

@test "models: --model replaces only the model and keeps the profile's other flags" {
  run_script beam-agent.sh --profile codex-terra --model openai.gpt-6-luna alpha-one review
  [ "$status" -eq 0 ]
  grep -q 'agent start codex .*-- --model openai.gpt-6-luna -c model_reasoning_effort="medium" --sandbox workspace-write --ask-for-approval on-request' "$FAKE_LOG"
}

@test "models: --model needs a value and a profile, and rejects control characters" {
  run_script beam-agent.sh --profile codex-sol --model
  [ "$status" -ne 0 ]
  [[ "$output" == *'--model requires a model name'* ]]
  run_script beam-agent.sh --model openai.gpt-6-luna alpha-one
  [ "$status" -ne 0 ]
  [[ "$output" == *'--model needs a profile'* ]]
  run_script beam-agent.sh --profile codex-sol --model $'gpt\x01' alpha-one
  [ "$status" -ne 0 ]
  [[ "$output" == *'invalid model name'* ]]
  ! grep -q 'workspace create' "$FAKE_LOG"
}

@test "models: new refuses a model the tenant does not offer before creating a Beam" {
  run_script beam-new.sh --agent --profile codex-sol --model gpt-0
  [ "$status" -ne 0 ]
  [[ "$output" == *'gpt-0 is not offered on example.beams.sh'* ]]
  ! grep -q 'beams add' "$FAKE_LOG"
}

@test "models: picker lists the tenant's models, marks the default, and Enter keeps it" {
  run_interactive beam-profiles.sh alpha-one <<<$'3\n\nreview\ncheck it\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'codex models on example.beams.sh:'*'1) openai.gpt-6-luna'*'2) openai.gpt-6.1-sol · profile default'*'5) zai.glm-5'* ]]
  [[ "$output" == *'enter keep openai.gpt-6.1-sol · number use another model'*'Model [openai.gpt-6.1-sol]:'*'Workspace label'* ]]
  grep -q 'agent start codex .*--model openai.gpt-6.1-sol' "$FAKE_LOG"
}

@test "models: picker uses another model by number with the profile's other settings" {
  run_interactive beam-profiles.sh alpha-one <<<$'3\n4\nreview\ncheck it\n'
  [ "$status" -eq 0 ]
  grep -q 'agent start codex .*-- --model openai.gpt-6.2-sol -c model_reasoning_effort="high"' "$FAKE_LOG"
}

@test "models: picker cancels an invalid model choice without launching" {
  for choice in 0 6 nope; do
    : > "$FAKE_LOG"
    run_interactive beam-profiles.sh alpha-one <<<$'3\n'"$choice"$'\n'
    [ "$status" -ne 0 ]
    [[ "$output" == *'no model chosen'* ]]
    ! grep -q 'workspace create\|integration install' "$FAKE_LOG"
  done
}

@test "models: picker with a stale profile default needs a number, and empty cancels" {
  printf '%s' '{"old":{"harness":"claude","model":"anthropic.claude-opus-5","effort":"high","approval":"default"}}' \
    > "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
  run_interactive beam-profiles.sh alpha-one <<<$'5\n\n'
  [ "$status" -ne 0 ]
  [[ "$output" == *'anthropic.claude-opus-5 from the profile is not offered on example.beams.sh'*'number pick a model · empty cancel'* ]]
  [[ "$output" == *'no model chosen'* ]]
  ! grep -q 'workspace create' "$FAKE_LOG"
  run_interactive beam-profiles.sh alpha-one <<<$'5\n1\napi\n\n'
  [ "$status" -eq 0 ]
  grep -q 'agent start claude .*--model anthropic.claude-opus-5-5 --effort high' "$FAKE_LOG"
}

@test "models: picker skips the model question with no list or a single offered model" {
  touch "$FAKE_STATE/apps-fails"
  run_interactive beam-profiles.sh alpha-one <<<$'3\nreview\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'could not read the model list on example.beams.sh; using openai.gpt-6.1-sol from the profile'* ]]
  [[ "$output" != *'Model'* ]]
  rm "$FAKE_STATE/apps-fails"
  openai_models '[{"name":"openai.gpt-6.1-sol"}]'
  run_interactive beam-profiles.sh alpha-one <<<$'3\nreview\n\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *'Model'* ]]
  grep -q 'agent start codex .*--model openai.gpt-6.1-sol' "$FAKE_LOG"
}

@test "models: a picked model survives Beam creation without a second question" {
  printf '[]' > "$FAKE_STATE/beams.json"
  run_bound beam-profiles.sh <<<$'3\n1\napi\nfix it\n'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -o 'Model \[' | wc -l)" -eq 1 ]
  calls_in_order 'beams add' 'machine add' 'agent start codex --kind codex --pane w9:p1 -- --model openai.gpt-6-luna'
}

@test "models, in a Beam: the picker reads the list and the launch uses the picked model" {
  run_in_beam beam-profiles.sh <<<$'1\n2\nreview\n\n'
  [ "$status" -eq 0 ]
  grep -q 'tsh --proxy=example.beams.sh apps ls -f json' "$FAKE_LOG"
  grep -q 'agent start claude .*--model anthropic.claude-sonnet-5 --effort high' "$FAKE_LOG"
  ! grep -q -- '--machine' "$FAKE_LOG"
}

@test "models, in a Beam: a refused listing leaves the launch unchecked" {
  touch "$FAKE_STATE/apps-fails"
  run_in_beam beam-claude.sh review '' </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *'launching anthropic.claude-opus-5-5 unchecked'* ]]
  grep -q 'agent start claude' "$FAKE_LOG"
}

@test "models: the startup hook refreshes the catalog alongside the registrations" {
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [ "$(catalog | jq -r .proxy)" = example.beams.sh ]
  touch "$FAKE_STATE/apps-fails"
  run_script beam-reconcile.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *'could not read the model list on example.beams.sh; launches will try again'* ]]
  [ "$(catalog | jq -r .proxy)" = example.beams.sh ]
}
