#!/usr/bin/env bats

@test "validation runner: rejects a syntax error after the first script" {
  root="$BATS_TEST_TMPDIR/runner"
  mkdir -p "$root/bin" "$root/demo" "$root/tests/fakes" "$root/tools"
  cp "$BATS_TEST_DIRNAME/../run.sh" "$root/tests/run.sh"
  printf 'true\n' > "$root/bin/a.sh"
  printf 'if then\n' > "$root/bin/b.sh"
  printf 'true\n' > "$root/demo/demo.sh"
  printf 'true\n' > "$root/tests/fakes/fake"
  for tool in shellcheck bats; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$root/tools/$tool"
    chmod +x "$root/tools/$tool"
  done
  run env PATH="$root/tools:$PATH" bash "$root/tests/run.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *'bin/b.sh'*'syntax error'* ]]
}
