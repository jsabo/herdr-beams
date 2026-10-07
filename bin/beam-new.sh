#!/usr/bin/env bash
# Create a Beam, install herdr on it, add it to the herdr sidebar, and
# optionally start an agent in it. Runs in a popup pane. Prints a timestamp
# per phase so you can see where the seconds go.
# Usage: beam-new.sh [--agent]
#   --agent  hand over to beam-agent.sh for the new Beam without asking; this
#            is how the agent pane creates a Beam when there is none.
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
then_agent=0
[ "${1:-}" != --agent ] || then_agent=1
header "New Beam"

# Provisioning takes about ten seconds on the server, so the Beam list the
# reconcile needs is fetched while that runs instead of before it. This is the
# one pane where quick_reconcile is not the first thing after the header.
busy "creating a Beam on $BEAMS_PROXY"
add_json="$(mktemp)"
tshb add --no-console -f json > "$add_json" &
add_pid=$!
quick_reconcile
wait "$add_pid" \
  || die "tsh beams add failed on $BEAMS_PROXY; if you are not logged in: TELEPORT_CLUSTER= tsh login --proxy=$BEAMS_PROXY"
beam="$(cat "$add_json")"
rm -f "$add_json"
id="$(jq -r .id <<<"$beam")"
uuid="$(jq -r .uuid <<<"$beam")"
expires="$(jq -r .expires <<<"$beam")"
host="$(beam_host "$uuid")"
remember_beam "$beam"
phase "Beam $id created ($uuid), expires $(cut -c1-16 <<<"$expires")Z"
# From here on a failure leaves a Beam that costs sandbox time; say so.
FAIL_HINT="Beam $id exists without a sidebar entry; remove it with the rm pane or: bash bin/beam-rm.sh $id"

busy "waiting for the Beam to accept SSH"
wait_for_ssh "$host"
phase "SSH up"

version="$(prepare_beam "$host")"
phase "$version installed, $BEAM_AGENT_KIND integration and Beam notes in place"

# herdr's own discovery and server start on the Beam; about five seconds.
busy "starting herdr's server on the Beam"
machine="$(machine_label "$id")"
"$HERDR" machine add "ssh://$host" --label "$machine" </dev/null >/dev/null
refresh_machines
save_state
FAIL_HINT=""
phase "$id is in the sidebar as $machine; its herdr server is running"

printf '\n'
card_open "$id"
card_line "$C_OK$G_OK$C_RESET in the sidebar · $version on the Beam"
card_line "expires $(cut -c1-16 <<<"$expires" | tr T ' ') UTC · $(expires_in "$expires")"
card_line "ssh $host"
card_close
printf '\n'
note "from any shell:"
show_cmd "herdr --machine $machine pane list"

if [ "$then_agent" = 1 ]; then
  printf '\n'
  exec bash bin/beam-agent.sh "$id"
fi
# The offer doubles as the close key: any key closes, y goes on to the agent.
if interactive; then
  printf '\n'
  hints "y start a $BEAM_AGENT_KIND agent in it now" "any other key close"
  yn=""
  ask "Start a $BEAM_AGENT_KIND agent in it now? [y/N] " yn
  case "$yn" in
    y|Y) exec bash bin/beam-agent.sh "$id" ;;
  esac
fi
pause
