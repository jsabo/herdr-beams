#!/usr/bin/env bats
load '../helpers'
setup() { setup_fakes; }

@test "codex process: installs a one-use scoped hint before normal agent startup" {
  run_script beam-codex.sh alpha-one review 'check it'
  [ "$status" -eq 0 ]
  calls_in_order 'workspace create' \
    'pane run w9:p1 codex() { unset -f codex; printf "\033[H\033[2J\033[3J"; HERDR_AGENT=codex command codex "$@"; }' \
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
    codex "model with spaces" '\''literal $(no-command)'\'' > "$FAKE_STATE/codex-stdout"
    test "$?" -eq 7 || exit 10
    declare -F codex >/dev/null && exit 11
    test -z "${HERDR_AGENT+x}" || exit 12
    command codex after
    test "$?" -eq 7
  '
  [ "$status" -eq 0 ]
  run bash -c 'mapfile -d "" -t args < "$FAKE_STATE/codex-executions"; printf "<%s>\n" "${args[@]}"'
  [ "$output" = $'<codex>\n<model with spaces>\n<literal $(no-command)>\n<unset>\n<after>' ]

  # The shim clears the pane before Codex runs, so its header starts at the top
  # like Claude Code's, which clears the screen itself. It writes the escape
  # sequence rather than calling `clear`: a herdr pane runs with
  # TERM=xterm-ghostty and the Beam image has no terminfo entry for it.
  run cat -v "$FAKE_STATE/codex-stdout"
  [ "$output" = '^[[H^[[2J^[[3J' ]
}

@test "codex process: names the agent on its workspace, after the launch" {
  run_script beam-codex.sh alpha-one review
  [ "$status" -eq 0 ]
  # A space row has no agent token, so the machines rail can only name what is
  # running here from a token the plugin reports: { token = "$agent" }.
  calls_in_order 'agent start codex' \
    'workspace report-metadata w9 --source herdr-beams --token agent=codex'
  # display-only: it never touches the agent name herdr detected
  ! grep -q 'display-agent' "$FAKE_LOG"
}

@test "codex process: a failed workspace label leaves the agent running" {
  touch "$FAKE_STATE/report-metadata-fails"
  run_script beam-codex.sh alpha-one review
  [ "$status" -eq 0 ]
  [[ "$output" == *'could not name codex in the machines rail'* ]]
  grep -q 'agent start codex' "$FAKE_LOG"
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
  # every launch names its agent on its workspace, for the machines rail
  grep -q 'workspace report-metadata w9 --source herdr-beams --token agent=claude' "$FAKE_LOG"
}
