#!/usr/bin/env bats
load '../helpers'
setup() { setup_fakes; }

@test "codex process: installs a one-use scoped hint before normal agent startup" {
  run_script beam-codex.sh alpha-one review 'check it'
  [ "$status" -eq 0 ]
  calls_in_order 'workspace create' \
    'pane run w9:p1 codex() { unset -f codex; HERDR_AGENT=codex command codex "$@"; }' \
    'agent start codex --kind codex --pane w9:p1 -- --model openai.gpt-5.6-sol' \
    'agent prompt codex check it'

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/codex" <<'CODEX'
#!/usr/bin/env bash
printf '%s\0' "${HERDR_AGENT:-unset}" "$@" >> "$FAKE_STATE/codex-executions"
exit 7
CODEX
  chmod +x "$BATS_TEST_TMPDIR/bin/codex"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
    unset HERDR_AGENT
    eval "$(cat "$FAKE_STATE/last-pane-command")"
    codex "model with spaces" '\''literal $(no-command)'\''
    test "$?" -eq 7 || exit 10
    declare -F codex >/dev/null && exit 11
    test -z "${HERDR_AGENT+x}" || exit 12
    command codex after
    test "$?" -eq 7
  '
  [ "$status" -eq 0 ]
  run bash -c 'mapfile -d "" -t args < "$FAKE_STATE/codex-executions"; printf "<%s>\n" "${args[@]}"'
  [ "$output" = $'<codex>\n<model with spaces>\n<literal $(no-command)>\n<unset>\n<after>' ]
}

@test "codex process: setup errors stop before launching another process" {
  touch "$FAKE_STATE/pane-run-fails"
  run_script beam-codex.sh alpha-one
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not prepare Codex process detection'* ]]
  ! grep -q 'agent start' "$FAKE_LOG"
}

@test "codex process: Claude launch does not install the Codex shim" {
  run_script beam-claude.sh alpha-one
  [ "$status" -eq 0 ]
  ! grep -q 'pane run\|HERDR_AGENT' "$FAKE_LOG"
  grep -q 'agent start claude' "$FAKE_LOG"
}
