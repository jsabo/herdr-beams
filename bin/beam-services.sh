#!/usr/bin/env bash
# List the beam-init services in a Beam and follow one service's logs.
# Usage: beam-services.sh [beam-id] [service]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Beam services"
quick_reconcile

id="$(pick_beam "${1:-}")"
host="$(beam_host "$(beam_uuid "$id")")"
svc="${2:-}"

card_open "beam-init services on $id"
beam_ssh "$host" 'beamctl list' | while IFS= read -r line; do card_line "$line"; done
card_close
printf '\n'

if [ -z "$svc" ] && interactive; then
  hints "service name follow its logs" "enter close"
  ask "Follow logs of service (empty to close): " svc
fi
if [ -n "$svc" ]; then
  note "following: beamctl logs --follow $svc"
  exec ssh "${SSH_OPTS[@]}" -t "$host" "beamctl logs --follow $(printf '%q' "$svc")"
fi
pause
