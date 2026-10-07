#!/usr/bin/env bash
# Delete every Beam on the tenant and drop their herdr machine profiles: the
# one-key teardown. Lists what will go, asks once from the plugin menu (not
# from a keybinding, BEAMS_YES=1, nor without a terminal), then removes each
# Beam the way beam-rm does (profile first, so the sidebar never shows a dead
# entry).
# Usage: beam-rm-all.sh
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Remove every Beam"
quick_reconcile

mapfile -t ids < <(beams_json | jq -r '.[].id')
if [ "${#ids[@]}" -eq 0 ]; then
  off "no Beams on $BEAMS_PROXY; nothing to remove"
  pause
  exit 0
fi

for id in "${ids[@]}"; do
  if [ -n "$(machine_id "$id")" ]; then
    busy "$id (in the sidebar)"
  else
    busy "$id"
  fi
done
printf '\n'

if must_confirm; then
  hints "y delete all ${#ids[@]}" "any other key keep them"
  yn=""
  ask "Delete ${#ids[@]} Beam(s) and everything in them? [y/N] " yn
  case "$yn" in y|Y) ;; *) exit 0 ;; esac
fi

for id in "${ids[@]}"; do
  pid="$(machine_id "$id")"
  if [ -n "$pid" ]; then
    "$HERDR" machine remove "$pid" >/dev/null
    off "sidebar entry for $id removed"
  fi
  tshb rm "$id"
  forget_beam "$id"
done
save_state
ok "removed ${#ids[@]} Beam(s); $BEAMS_PROXY has none left"
pause
