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
