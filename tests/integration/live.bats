#!/usr/bin/env bats
# Runs the real scripts against the real tenant. Opt in with
# HERDR_BEAMS_INTEGRATION=1; needs a logged-in tsh, herdr, and the plugin's
# env file in place. Creates one Beam and deletes it at the end.

setup_file() {
  [ "${HERDR_BEAMS_INTEGRATION:-}" = 1 ] || skip "set HERDR_BEAMS_INTEGRATION=1 to run"
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export REPO
  export HERDR_PLUGIN_CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr/plugins/config/herdr-beams}"
  export HERDR_PLUGIN_STATE_DIR="$BATS_FILE_TMPDIR/state"
  [ -f "$HERDR_PLUGIN_CONFIG_DIR/env" ] || skip "no $HERDR_PLUGIN_CONFIG_DIR/env"
  # shellcheck disable=SC1091
  . "$HERDR_PLUGIN_CONFIG_DIR/env"
  export BEFORE="$BATS_FILE_TMPDIR/before.json"
  tsh --proxy="$BEAMS_PROXY" beams ls -f json > "$BEFORE" || skip "not logged in to $BEAMS_PROXY"
  cd "$REPO" || exit 1
}

# The sidebar label and `--machine` selector for a Beam, as bin/common.sh builds it.
machine_of() { printf '%s%s' "${BEAM_LABEL_PREFIX-beam/}" "$1"; }

# The SSH address of a Beam, beams@<uuid>.<tenant>, as bin/common.sh builds it.
# The settings are sourced here because each test body is its own process.
host_of() {
  # shellcheck disable=SC1091
  . "$HERDR_PLUGIN_CONFIG_DIR/env"
  local uuid
  uuid="$(tsh --proxy="$BEAMS_PROXY" beams ls -f json | jq -r --arg id "$1" '.[] | select(.id == $id) | .uuid')"
  printf '%s@%s.%s' "${BEAM_LOGIN:-beams}" "$uuid" "${BEAMS_PROXY%%:*}"
}

# The Beam this run created: present now, absent before.
new_beam() {
  # shellcheck disable=SC1091
  . "$HERDR_PLUGIN_CONFIG_DIR/env"
  tsh --proxy="$BEAMS_PROXY" beams ls -f json \
    | jq -r --slurpfile b "$BEFORE" '.[] | select(.id as $id | ($b[0] | map(.id) | index($id)) == null) | .id' | head -1
}

teardown_file() {
  [ "${HERDR_BEAMS_INTEGRATION:-}" = 1 ] || return 0
  id="$(new_beam || true)"
  if [ -n "$id" ]; then
    bash "$REPO/bin/beam-rm.sh" "$id" </dev/null || true
  fi
}

@test "live: new Beam appears as a reachable herdr machine" {
  run bash bin/beam-new.sh </dev/null
  [ "$status" -eq 0 ]
  id="$(new_beam)"
  [ -n "$id" ]
  run herdr machine status "$(machine_of "$id")" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "reachable"'* ]]
}

@test "live: an agent started from the laptop reaches done" {
  id="$(new_beam)"
  run bash bin/beam-agent.sh "$id" smoke "Reply with the single word: ready. Do not run tools." </dev/null
  [ "$status" -eq 0 ]
  for _ in $(seq 1 30); do
    # a fresh Beam has exactly one agent; its name follows BEAM_AGENT_KIND, not the workspace label
    state="$(herdr --machine "$(machine_of "$id")" agent list | jq -r '.result.agents[0].agent_status')"
    [ "$state" = done ] && break
    sleep 2
  done
  [ "$state" = done ]
}

@test "live: the Beam carries this plugin and the key block, so its keys work" {
  id="$(new_beam)"
  machine="$(machine_of "$id")"
  # `new` installed the plugin on the Beam before its herdr server started.
  run herdr --machine "$machine" plugin list
  [ "$status" -eq 0 ]
  [[ "$output" == *"herdr-beams"* ]]
  # The key block is in the Beam's own herdr config, which is what makes the
  # keys exist while that Beam is the selected machine.
  run ssh -o BatchMode=yes "$(host_of "$id")" 'cat ~/.config/herdr/config.toml'
  [ "$status" -eq 0 ]
  [[ "$output" == *"# herdr-beams-keys"* ]]
  [[ "$output" == *'command = "herdr-beams.claude"'* ]]
  # The Beam-side settings say which Beam this is, which is what switches the
  # entrypoints to their single-Beam behaviour.
  run ssh -o BatchMode=yes "$(host_of "$id")" \
    'cat "$(~/.local/bin/herdr plugin config-dir herdr-beams)/env"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEAM_SELF_ID=$id"* ]]
  [[ "$output" == *"BEAM_SELF_UUID="* ]]
  # The Beam's herdr publishes the plugin's actions, which is where a key goes.
  run herdr --machine "$machine" plugin action list
  [ "$status" -eq 0 ]
  [[ "$output" == *"herdr-beams"* ]]
}

@test "live: a Beam-side action starts an agent in that Beam, as its keybinding would" {
  id="$(new_beam)"
  machine="$(machine_of "$id")"
  # The Beam installs the published plugin, not this checkout, so this only
  # means anything once 0.9.0 is on GitHub. The `keys` action is 0.9.0 or newer.
  actions="$(herdr --machine "$machine" plugin action list)"
  grep -q '"action_id":"keys"' <<<"$actions" \
    || skip "the Beam installed a plugin older than 0.9.0; push this branch to test the Beam-side action"
  before="$(herdr --machine "$machine" agent list | jq '.result.agents | length')"
  # This is the keybinding path: the action runs on the Beam's own server, from
  # the plugin installed there, with no laptop script involved.
  run herdr --machine "$machine" plugin action invoke herdr-beams.claude
  [ "$status" -eq 0 ]
  for _ in $(seq 1 30); do
    after="$(herdr --machine "$machine" agent list | jq '.result.agents | length')"
    [ "$after" -gt "$before" ] && break
    sleep 2
  done
  [ "$after" -gt "$before" ]
}

@test "live: services pane lists nothing on a fresh Beam, status shows it" {
  id="$(new_beam)"
  run bash bin/beam-services.sh "$id" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"beam-init services on $id"* ]]
  run bash bin/beam-status.sh </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"$id"*"in the sidebar"* ]]
}

@test "live: rm deletes the Beam and its profile" {
  id="$(new_beam)"
  run bash bin/beam-rm.sh "$id" </dev/null
  [ "$status" -eq 0 ]
  run herdr machine list --json
  [[ "$output" != *"\"$id\""* ]]
  [ -z "$(new_beam)" ]
}
