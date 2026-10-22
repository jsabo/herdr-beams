#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

uuid="aaaaaaaa-0000-4000-8000-000000000001"
host="beams@aaaaaaaa-0000-4000-8000-000000000001.example.beams.sh"

# The program the Beam runs, as common.sh prints it. common.sh re-execs itself
# under a modern Bash by path, so the caller has to be a file, not `bash -c`.
setup_program() {
  printf '%s\n' '. bin/common.sh' 'beam_setup_program "$1" "$2"' > "$BATS_TEST_TMPDIR/print-program.sh"
  bash "$BATS_TEST_TMPDIR/print-program.sh" "$1" "$2"
}

# One of its two base64 payloads, decoded: beams_env or beams_keys.
payload() {
  setup_program "$2" "$3" | sed -n "s/^$1=\\(.*\\)\$/\\1/p" | tr -d "'" | base64 -d
}

# Run the program as the Beam would, against a throwaway HOME. The fake herdr
# answers plugin list/install/config-dir, so the remote half runs offline.
sandbox_home="" # set by sandbox_run
sandbox_run() {
  sandbox_home="$BATS_TEST_TMPDIR/beam-home"
  mkdir -p "$sandbox_home"
  run env HOME="$sandbox_home" XDG_CONFIG_HOME="$sandbox_home/.config" \
    HERDR_PLUGIN_CONFIG_DIR="$sandbox_home/plugin-config" PATH="$REPO/tests/fakes:$PATH" \
    bash -c "$(setup_program alpha-one "$uuid")"
}

@test "keys: the program the Beam runs is valid shell" {
  # shellcheck cannot see inside the string common.sh builds, so syntax-check
  # the real thing here: a broken remote program would otherwise only show up
  # on a Beam.
  setup_program alpha-one uuid-1 > "$BATS_TEST_TMPDIR/program.sh"
  run bash -n "$BATS_TEST_TMPDIR/program.sh"
  [ "$status" -eq 0 ]
}

@test "keys: the env file it writes names this Beam and carries the settings" {
  run payload beams_env alpha-one "$uuid"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEAM_SELF_ID=alpha-one"* ]]
  [[ "$output" == *"BEAM_SELF_UUID=$uuid"* ]]
  [[ "$output" == *"BEAMS_PROXY=example.beams.sh"* ]]
  [[ "$output" == *"BEAM_AGENT_KIND=claude"* ]]
}

@test "keys: the block it appends is config/beam-keys.toml, marker and all" {
  run payload beams_keys alpha-one "$uuid"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat config/beam-keys.toml)" ]
  [[ "${lines[0]}" = "# herdr-beams-keys" ]]
  [[ "$output" == *'command = "herdr-beams.claude"'* ]]
}

@test "keys: the key block avoids every herdr default binding" {
  # A custom command claims its key before herdr parses its defaults, and the
  # colliding default is then dropped with no warning, so a collision costs the
  # user a herdr action (herdr 0.9.x, src/config/keybinds.rs:651 and :1099-1102).
  for key in prefix+question prefix+s prefix+q prefix+o prefix+w prefix+g \
             prefix+c prefix+p prefix+n prefix+e prefix+v prefix+x prefix+z \
             prefix+r prefix+b prefix+h prefix+j prefix+k prefix+l prefix+minus \
             prefix+tab prefix+shift+tab \
             prefix+shift+r prefix+shift+n prefix+shift+g prefix+shift+w \
             prefix+shift+d prefix+shift+t prefix+shift+x prefix+shift+p; do
    ! grep -q "^key = \"$key\"\$" config/beam-keys.toml || { echo "collides: $key"; return 1; }
  done
}

@test "keys: every key in the block is the prefix, shift and one letter" {
  mapfile -t keys < <(sed -nE 's/^key = "(.*)"$/\1/p' config/beam-keys.toml)
  [ "${#keys[@]}" -eq 9 ]
  for key in "${keys[@]}"; do
    [[ "$key" =~ ^prefix\+shift\+[a-z]$ ]] || { echo "not prefix+shift+<letter>: $key"; return 1; }
  done
  # the initial of the thing: Beam, Claude, OpenAI, Agent, Status, Logs, Expose,
  # Kill, Quit
  [ "${keys[*]}" = "prefix+shift+b prefix+shift+c prefix+shift+o prefix+shift+a prefix+shift+s prefix+shift+l prefix+shift+e prefix+shift+k prefix+shift+q" ]
}

@test "keys: every action the block binds exists in the manifest" {
  mapfile -t bound < <(sed -nE 's/^command = "herdr-beams\.(.*)"$/\1/p' config/beam-keys.toml)
  [ "${#bound[@]}" -eq 9 ]
  for id in "${bound[@]}"; do
    grep -q "^id = \"$id\"\$" herdr-plugin.toml || { echo "no such action: $id"; return 1; }
  done
}

@test "keys: the README recommends exactly the block a Beam gets" {
  # The README block is the one a reader copies into their own config, so it has
  # to be the same keys and the same actions, in the same order.
  diff <(sed -nE 's/^(key|command) = "(.*)"$/\2/p' config/beam-keys.toml) \
       <(awk '/^## Keybindings$/{k=1} k && /^### /{exit} k' README.md \
         | sed -nE 's/^(key|command) = "(.*)"$/\2/p')
}

@test "keys: run on the Beam, the program installs the plugin, the settings and the block" {
  touch "$FAKE_STATE/plugin-not-installed"
  sandbox_run
  [ "$status" -eq 0 ]
  # --yes is required when stdin is not a terminal, which it never is here
  grep -q "herdr plugin install --yes jsabo/herdr-beams" "$FAKE_LOG"
  grep -q "BEAM_SELF_ID=alpha-one" "$sandbox_home/plugin-config/env"
  grep -q "^# herdr-beams-keys\$" "$sandbox_home/.config/herdr/config.toml"
  grep -q 'command = "herdr-beams.claude"' "$sandbox_home/.config/herdr/config.toml"
}

@test "keys: it leaves an already installed plugin alone" {
  sandbox_run
  [ "$status" -eq 0 ]
  [ "$(call_count 'plugin install')" -eq 0 ]
}

@test "keys: running it twice appends the block once" {
  sandbox_run
  [ "$status" -eq 0 ]
  sandbox_run
  [ "$status" -eq 0 ]
  [ "$(grep -c '^# herdr-beams-keys$' "$sandbox_home/.config/herdr/config.toml")" -eq 1 ]
  [ "$(grep -c 'command = "herdr-beams.claude"' "$sandbox_home/.config/herdr/config.toml")" -eq 1 ]
}

@test "keys: it keeps what the Beam's config already said" {
  sandbox_home="$BATS_TEST_TMPDIR/beam-home"
  mkdir -p "$sandbox_home/.config/herdr"
  printf '[theme]\nname = "mine"\n' > "$sandbox_home/.config/herdr/config.toml"
  sandbox_run
  [ "$status" -eq 0 ]
  grep -q 'name = "mine"' "$sandbox_home/.config/herdr/config.toml"
  grep -q '^# herdr-beams-keys$' "$sandbox_home/.config/herdr/config.toml"
}

@test "keys: the pane sends the program to the Beam and reloads its herdr config" {
  run_script beam-keys.sh alpha-one
  [ "$status" -eq 0 ]
  calls_in_order \
    "ssh" \
    "herdr --machine id-alpha-one server reload-config"
  grep -q "^ssh .*$host beams_env=" "$FAKE_LOG"
  grep -q "plugin config-dir herdr-beams" "$FAKE_LOG"
  [[ "$output" == *"plugin, settings and key block in place on alpha-one"* ]]
  [[ "$output" == *"the Beams keys work while alpha-one is selected"* ]]
}

@test "keys: a failed install on the Beam fails the pane and skips the reload" {
  touch "$FAKE_STATE/keys-setup-fails"
  run_script beam-keys.sh alpha-one
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not install the plugin on alpha-one"* ]]
  [ "$(call_count 'server reload-config')" -eq 0 ]
}

@test "keys: a Beam whose herdr does not reload says the keys are already there" {
  touch "$FAKE_STATE/reload-config-fails"
  run_script beam-keys.sh alpha-one
  [ "$status" -eq 1 ]
  [[ "$output" == *"the keys are on alpha-one but its herdr did not reload"* ]]
}

@test "keys: a Beam without a sidebar entry gets the block and no reload" {
  jq 'map(select(.id != "id-alpha-one"))' "$FAKE_STATE/machines.json" > "$FAKE_STATE/m.tmp"
  mv "$FAKE_STATE/m.tmp" "$FAKE_STATE/machines.json"
  run_script beam-keys.sh alpha-one
  [ "$status" -eq 0 ]
  [[ "$output" == *"has no sidebar entry yet"* ]]
  [ "$(call_count 'server reload-config')" -eq 0 ]
}

@test "keys: an unknown Beam is rejected before any ssh" {
  run_script beam-keys.sh nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"* ]]
  ! grep -q "^ssh" "$FAKE_LOG"
}

@test "keys: inside a Beam the pane says it belongs on the laptop" {
  run_in_beam beam-keys.sh </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"runs on your laptop, not inside a Beam"* ]]
  ! grep -q "^ssh" "$FAKE_LOG"
}

@test "keys: a config without a trailing newline still gets a readable marker" {
  sandbox_home="$BATS_TEST_TMPDIR/beam-home"
  mkdir -p "$sandbox_home/.config/herdr"
  printf '[theme]\nname = "mine"' > "$sandbox_home/.config/herdr/config.toml"  # no newline
  sandbox_run
  [ "$status" -eq 0 ]
  grep -q '^# herdr-beams-keys$' "$sandbox_home/.config/herdr/config.toml"
  grep -q '^name = "mine"$' "$sandbox_home/.config/herdr/config.toml"
  # and a second run still recognises it
  sandbox_run
  [ "$(grep -c '^# herdr-beams-keys$' "$sandbox_home/.config/herdr/config.toml")" -eq 1 ]
}

@test "keys: a successful install says nothing, preview and all" {
  touch "$FAKE_STATE/plugin-not-installed"
  sandbox_run
  [ "$status" -eq 0 ]
  # The real `plugin install` prints its manifest preview to stderr on success;
  # a popup should show none of it. Measured on a live Beam, 2026-10-22.
  [[ "$output" != *"Plugin install preview"* ]]
  [ -z "$output" ]
}

@test "keys: a failed install shows what herdr said" {
  touch "$FAKE_STATE/plugin-not-installed" "$FAKE_STATE/plugin-install-fails"
  sandbox_run
  [ "$status" -ne 0 ]
  [[ "$output" == *"install failed"* ]]
  # it stopped there: no settings and no key block on a Beam without the plugin
  [ ! -e "$sandbox_home/plugin-config/env" ]
}
