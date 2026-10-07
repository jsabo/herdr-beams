#!/usr/bin/env bash
# Delete a Beam and drop its herdr machine profile. Asks first from the plugin
# menu; from a keybinding (BEAMS_YES=1) or without a terminal it just deletes.
# Usage: beam-rm.sh [beam-id]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Remove a Beam"
quick_reconcile

id="$(pick_beam "${1:-}")"
if must_confirm; then
  hints "y delete $id" "any other key keep it"
  yn=""
  ask "Delete Beam $id and everything in it? [y/N] " yn
  case "$yn" in y|Y) ;; *) exit 0 ;; esac
fi

pid="$(machine_id "$id")"
if [ -n "$pid" ]; then
  "$HERDR" machine remove "$pid" >/dev/null
  off "sidebar entry for $id removed"
fi
tshb rm "$id"
forget_beam "$id"
save_state
ok "removed $id"
pause
