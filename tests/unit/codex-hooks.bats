#!/usr/bin/env bats
load '../helpers'
setup() { setup_fakes; }

@test "codex hooks: trust uses Codex hash and updates only the installed Herdr hook" {
  cat > "$FAKE_STATE/codex-hooks.json" <<'JSON'
{"data":[{"hooks":[
 {"key":"expected","eventName":"sessionStart","handlerType":"command","command":"bash '/home/beams/.codex/herdr-agent-state.sh' session","sourcePath":"/home/beams/.codex/hooks.json","enabled":true,"currentHash":"sha256:fresh"},
 {"key":"unrelated","eventName":"sessionStart","handlerType":"command","command":"echo unrelated","sourcePath":"/home/beams/.codex/hooks.json","enabled":true,"currentHash":"sha256:other"}
]}]}
JSON
  run_script beam-codex.sh alpha-one review
  [ "$status" -eq 0 ]
  jq -es 'map(select(.method == "config/batchWrite")) | length == 1 and
    .[0].params.edits == [{keyPath:"hooks.state",value:{expected:{trusted_hash:"sha256:fresh"}},mergeStrategy:"upsert"}]' "$FAKE_STATE/codex-rpc.log"
  ! grep -q 'dangerously-bypass-hook-trust' "$FAKE_LOG"
  grep -q 'agent start codex' "$FAKE_LOG"
}

@test "codex hooks: wrong source, command injection, disabled hooks and duplicate matches fail before creating workspaces" {
  for change in '.sourcePath="/project/.codex/hooks.json"' '.command += "; echo injected"' '.enabled=false' '.eventName="stop"'; do
    jq -n --arg change "$change" '{data:[{hooks:[{key:"expected",eventName:"sessionStart",handlerType:"command",command:"bash '\''/home/beams/.codex/herdr-agent-state.sh'\'' session",sourcePath:"/home/beams/.codex/hooks.json",enabled:true,currentHash:"sha256:fresh"}]}]}' > "$FAKE_STATE/original-hooks.json"
    jq ".data[0].hooks[0] |= ($change)" "$FAKE_STATE/original-hooks.json" > "$FAKE_STATE/codex-hooks.json"
    run_script beam-codex.sh alpha-one
    [ "$status" -ne 0 ]
    [[ "$output" == *'could not identify the installed Herdr Codex hook'* ]]
    ! grep -q 'workspace create\|agent start' "$FAKE_LOG"
    ! grep -q 'config/batchWrite' "$FAKE_STATE/codex-rpc.log"
  done
  jq '.data[0].hooks += .data[0].hooks' "$FAKE_STATE/original-hooks.json" > "$FAKE_STATE/codex-hooks.json"
  run_script beam-codex.sh alpha-one
  [ "$status" -ne 0 ]
  ! grep -q 'workspace create\|agent start' "$FAKE_LOG"
}

@test "codex hooks: API and config write errors remain visible and prevent agent launch" {
  touch "$FAKE_STATE/codex-rpc-error"
  run_script beam-codex.sh alpha-one
  [ "$status" -ne 0 ]
  [[ "$output" == *'hooks/list unsupported'* ]]
  ! grep -q 'workspace create\|agent start' "$FAKE_LOG"
  rm "$FAKE_STATE/codex-rpc-error"
  touch "$FAKE_STATE/codex-write-error"
  run_script beam-codex.sh alpha-one
  [ "$status" -ne 0 ]
  [[ "$output" == *'config is read-only'* ]]
  ! grep -q 'workspace create\|agent start' "$FAKE_LOG"
}

@test "codex network: boolean overrides are explicit and do not change file sandbox or approvals" {
  printf '%s' '{"offline":{"harness":"codex","model":"proxy-model","effort":"high","approval":"never","sandbox":"workspace-write","network_access":false}}' > "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
  run bash -c '. bin/common.sh; load_agent_profile offline; printf "<%s>\n" "${AGENT_ARGS[@]}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'<--sandbox>'*'<workspace-write>'*'<--ask-for-approval>'*'<never>'*'<sandbox_workspace_write.network_access=false>'* ]]
  for field in '"yes"' 'null' '1'; do
    sed "s/false/$field/" "$HERDR_PLUGIN_CONFIG_DIR/profiles.json" > "$BATS_TEST_TMPDIR/invalid.json"
    cp "$BATS_TEST_TMPDIR/invalid.json" "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
    run_script beam-agent.sh --profile offline alpha-one
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid profiles'* ]]
    [ ! -s "$FAKE_LOG" ]
    printf '%s' '{"offline":{"harness":"codex","model":"proxy-model","effort":"high","approval":"never","sandbox":"workspace-write","network_access":false}}' > "$HERDR_PLUGIN_CONFIG_DIR/profiles.json"
  done
}
