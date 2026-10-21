#!/usr/bin/env bats
load '../helpers'

setup() {
  setup_fakes
  [ -n "${BASH32_BIN:-}" ] || skip 'set BASH32_BIN to test startup with Bash 3.2'
}

@test "runtime: Bash 3.2 switches to modern Bash and preserves relative entrypoint and arguments" {
  local modern
  modern="$(command -v bash)"
  mkdir -p "$BATS_TEST_TMPDIR/runtime"
  ln -s "$modern" "$BATS_TEST_TMPDIR/runtime/bash"
  export PATH="$BATS_TEST_TMPDIR/runtime:$PATH"
  cd "$REPO/bin"
  run "$BASH32_BIN" beam-codex.sh alpha-one 'review space' 'Read SPEC.md and start.' </dev/null
  [ "$status" -eq 0 ]
  calls_in_order \
    'workspace create --cwd ~ --label review space --no-focus' \
    'agent start codex --kind codex' \
    'agent prompt codex Read SPEC.md and start.'
  [[ "$output" != *'mapfile: command not found'* ]]
}

@test "runtime: Bash 3.2 without modern Bash gives an install hint before calling external services" {
  [ ! -x /opt/homebrew/bin/bash ] && [ ! -x /usr/local/bin/bash ] || skip 'Homebrew Bash is available'
  mkdir -p "$BATS_TEST_TMPDIR/runtime"
  ln -s "$BASH32_BIN" "$BATS_TEST_TMPDIR/runtime/bash"
  export PATH="$BATS_TEST_TMPDIR/runtime:$PATH"
  run "$BASH32_BIN" "$REPO/bin/beam-codex.sh" </dev/null
  echo "status=$status output=$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Bash 4+ is required'*'brew install bash'* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "runtime: remove-all also restarts before using mapfile" {
  local modern
  modern="$(command -v bash)"
  mkdir -p "$BATS_TEST_TMPDIR/runtime"
  ln -s "$modern" "$BATS_TEST_TMPDIR/runtime/bash"
  export PATH="$BATS_TEST_TMPDIR/runtime:$PATH"
  run "$BASH32_BIN" "$REPO/bin/beam-rm-all.sh" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *'removed 2 Beam(s)'* ]]
  [ "$(call_count 'tsh --proxy=example.beams.sh beams rm')" -eq 2 ]
}

@test "runtime: every pane, action launcher, startup hook and demo upgrades Bash before loading config" {
  local modern script
  modern="$(command -v bash)"
  mkdir -p "$BATS_TEST_TMPDIR/runtime"
  ln -s "$modern" "$BATS_TEST_TMPDIR/runtime/bash"
  export PATH="$BATS_TEST_TMPDIR/runtime:$PATH"
  cat > "$HERDR_PLUGIN_CONFIG_DIR/env" <<'CONFIG'
[ "${BASH_VERSINFO[0]}" -ge 4 ] || exit 99
printf 'modern Bash reached config\n'
exit 0
CONFIG
  for script in "$REPO"/bin/beam-*.sh "$REPO/demo/demo.sh"; do
    run "$BASH32_BIN" "$script" </dev/null
    [ "$status" -eq 0 ]
    [ "$output" = 'modern Bash reached config' ]
  done
  [ ! -s "$FAKE_LOG" ]
}

@test "runtime: profile picker launches successfully when started with Bash 3.2" {
  local modern
  modern="$(command -v bash)"
  mkdir -p "$BATS_TEST_TMPDIR/runtime"
  ln -s "$modern" "$BATS_TEST_TMPDIR/runtime/bash"
  export PATH="$BATS_TEST_TMPDIR/runtime:$PATH"
  run env BEAMS_INTERACTIVE=1 "$BASH32_BIN" "$REPO/bin/beam-profiles.sh" alpha-one review <<<'1'
  [ "$status" -eq 0 ]
  [[ "$output" != *'mapfile: command not found'* ]]
  [ "$(call_count 'workspace create')" -eq 1 ]
  [ "$(call_count 'agent start')" -eq 1 ]
}
