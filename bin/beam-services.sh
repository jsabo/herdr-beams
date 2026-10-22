#!/usr/bin/env bash
# List the beam-init services in a Beam and follow one service's logs. On the
# laptop that is `beamctl` over SSH; on the Beam itself, which is where a
# keybinding pressed while that Beam is selected runs, it is beamctl directly.
# Usage, on the laptop: beam-services.sh [beam-id] [service]
# Usage, on a Beam:     beam-services.sh [service]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Beam services"

if in_beam; then
  id="$BEAM_SELF_ID"
  host=""
  svc="${1:-}"
else
  quick_reconcile
  id="$(pick_beam "${1:-}")"
  host="$(beam_host "$(beam_uuid "$id")")"
  svc="${2:-}"
fi

card_open "beam-init services on $id"
beam_run "$host" 'beamctl list' | while IFS= read -r line; do card_line "$line"; done
card_close
printf '\n'

if [ -z "$svc" ] && interactive; then
  hints "service name follow its logs" "enter close"
  ask "Follow logs of service (empty to close): " svc
fi
if [ -n "$svc" ]; then
  note "following: beamctl logs --follow $svc"
  # On the Beam the pane is already a terminal; from the laptop SSH needs one.
  if in_beam; then exec beamctl logs --follow "$svc"; fi
  exec ssh "${SSH_OPTS[@]}" -t "$host" "beamctl logs --follow $(printf '%q' "$svc")"
fi
pause
