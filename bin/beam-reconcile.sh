#!/usr/bin/env bash
# Startup hook: make the sidebar match reality. Removes herdr machine
# profiles whose Beam has expired or been deleted, adds profiles for Beams
# that already have herdr installed, and refreshes the state file.
# Never asks questions; a missing login just logs and exits 0.
# Every pane runs the removal half on entry (quick_reconcile); only this
# hook attempts adds, because an add is an SSH round trip per Beam.
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh

if [ -z "$BEAMS_PROXY" ]; then
  printf 'beams: BEAMS_PROXY not set in %s/env; nothing to reconcile\n' "$CONFIG_DIR"
  exit 0
fi
if ! BEAMS_JSON="$(tshb ls -f json 2>/dev/null)"; then
  printf 'beams: not logged in to %s; nothing to reconcile\n' "$BEAMS_PROXY"
  exit 0
fi
export BEAMS_JSON

quick_reconcile

# Beams without a profile. Non-interactive add only succeeds when herdr is
# already on the Beam, which is exactly the case we want to pick up.
while IFS=$'\t' read -r id uuid; do
  if [ -z "$(machine_id "$id")" ]; then
    host="$(beam_host "$uuid")"
    if "$HERDR" machine add "ssh://$host" --label "$id" </dev/null >/dev/null 2>&1; then
      printf 'beams: added profile for %s\n' "$id"
      refresh_machines
    else
      printf 'beams: %s has no herdr yet; use the New Beam pane or run beam-agent\n' "$id"
    fi
  fi
done < <(beams_json | jq -r '.[] | [.id, .uuid] | @tsv')

save_state
