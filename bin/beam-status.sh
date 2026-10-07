#!/usr/bin/env bash
# One card per Beam: whether it has a sidebar entry, region, expiry, SSH
# address. Everything comes from the two cached lists, so the pane costs one
# Beam listing. Whether herdr can reach a Beam is the dot on its sidebar
# entry; this pane does not probe it again.
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Beam status"
quick_reconcile

count="$(beams_json | jq 'length')"
if [ "$count" -eq 0 ]; then
  off "no Beams on $BEAMS_PROXY"
  show_cmd "herdr plugin action invoke herdr-beams.new"
  pause
  exit 0
fi

beams_json | jq -r '.[] | [.id, .region, .expires, .uuid] | @tsv' \
| while IFS=$'\t' read -r id region expires uuid; do
    if [ -n "$(machine_id "$id")" ]; then
      st="in the sidebar as $(machine_label "$id")"
      glyph="$C_OK$G_OK$C_RESET"
    else
      st="no sidebar entry"
      glyph="$C_DIM$G_OFF$C_RESET"
    fi
    card_open "$id"
    card_line "$glyph $st · $region"
    card_line "expires $(printf '%s' "$expires" | cut -c1-16 | tr T ' ') UTC · $(expires_in "$expires")"
    card_line "ssh $(beam_host "$uuid")"
    card_close
  done

printf '\n'
note "drive one from any shell:"
show_cmd "herdr --machine $(machine_label '<beam>') agent list"
pause
