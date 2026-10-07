# Shared setup for the unit tests: fake tsh/herdr/ssh on PATH, fixture state,
# a throwaway plugin config and state directory, and a call log.

setup_fakes() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export REPO
  FAKES="$REPO/tests/fakes"
  export FAKE_STATE="$BATS_TEST_TMPDIR/state"
  export FAKE_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$FAKE_STATE"
  : > "$FAKE_LOG"
  cp "$REPO"/tests/fixtures/* "$FAKE_STATE/"

  export PATH="$FAKES:$PATH"
  export HERDR_BIN_PATH="$FAKES/herdr"
  export HERDR_PLUGIN_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export HERDR_PLUGIN_STATE_DIR="$BATS_TEST_TMPDIR/pstate"
  mkdir -p "$HERDR_PLUGIN_CONFIG_DIR"
  printf 'BEAMS_PROXY=example.beams.sh\n' > "$HERDR_PLUGIN_CONFIG_DIR/env"
  cd "$REPO" || exit 1
}

# The call log, one line per fake invocation, in order.
calls() { cat "$FAKE_LOG"; }

# Current fixture state.
beams_state() { cat "$FAKE_STATE/beams.json"; }
machines_state() { cat "$FAKE_STATE/machines.json"; }

# Mark the selected machine in the fixture, as the sidebar would.
select_machine() {
  jq --arg l "$1" 'map(.selected = (.label == $l))' "$FAKE_STATE/machines.json" \
    > "$FAKE_STATE/machines.json.tmp" && mv "$FAKE_STATE/machines.json.tmp" "$FAKE_STATE/machines.json"
}

# Run a script without a terminal on stdin, like a plugin action or a scripted call.
run_script() { run bash "$REPO/bin/$1" "${@:2}" </dev/null; }

# Run a script as if someone were at the keyboard of a popup. The answers come
# from the caller's stdin: run_interactive beam-rm.sh alpha-one <<<"n".
run_interactive() { run env BEAMS_INTERACTIVE=1 bash "$REPO/bin/$1" "${@:2}"; }

# Run a script as a keybinding opens it: someone at the keyboard, and BEAMS_YES=1
# from beam-open.sh, so y/N questions are skipped. Value questions still read stdin.
run_bound() { run env BEAMS_INTERACTIVE=1 BEAMS_YES=1 bash "$REPO/bin/$1" "${@:2}"; }

# Assert that each fixed-string pattern appears in the call log, in this order.
calls_in_order() {
  local last=0 want n
  for want in "$@"; do
    n="$(grep -n -F -- "$want" "$FAKE_LOG" | cut -d: -f1 | awk -v last="$last" '$1 > last' | head -1)"
    [ -n "$n" ] || { echo "missing or out of order: $want"; cat "$FAKE_LOG"; return 1; }
    last="$n"
  done
}

# Number of calls matching a fixed string.
call_count() { grep -c -F -- "$1" "$FAKE_LOG" || true; }
