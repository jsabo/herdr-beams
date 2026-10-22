#!/usr/bin/env bash
# One card per Beam: whether it has a sidebar entry, region, expiry, SSH
# address. Everything comes from the two cached lists, so the pane costs one
# Beam listing. Whether herdr can reach a Beam is the dot on its sidebar
# entry; this pane does not probe it again.
# Run on a Beam, which is where a keybinding pressed while that Beam is
# selected runs, it reports that one Beam from what the Beam itself knows.
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Beam status"

# On the Beam itself there is one Beam worth reporting on, and the laptop's
# sidebar is out of reach. The Beam list may be too: a Beam's delegated identity
# cannot reissue certificates, so `tsh beams ls` there is not guaranteed. What
# the Beam always knows is what the plugin wrote into its own settings and what
# beamctl reports, so that is the floor and the listing is a bonus.
if in_beam; then
  card_open "$BEAM_SELF_ID"
  card_line "$C_OK$G_OK$C_RESET this Beam · $BEAM_SELF_UUID"
  if self="$(tshb ls -f json 2>/dev/null | jq -er --arg u "$BEAM_SELF_UUID" \
      'map(select(.uuid == $u)) | if length == 1 then .[0] else error("not listed") end')"; then
    card_line "region $(jq -r .region <<<"$self")"
    expires="$(jq -r .expires <<<"$self")"
    card_line "expires $(printf '%s' "$expires" | cut -c1-16 | tr T ' ') UTC · $(expires_in "$expires")"
  else
    card_line "$C_DIM$G_OFF$C_RESET region and expiry need the laptop's login"
  fi
  card_line "services:"
  # The listing is a bonus here too, so a beamctl that is missing or unhappy
  # must not take the card down with it.
  if services="$(beamctl list 2>/dev/null)" && [ -n "$services" ]; then
    printf '%s\n' "$services" | while IFS= read -r line; do card_line "  $line"; done
  else
    card_line "  none running"
  fi
  card_close
  printf '\n'
  note "the whole fleet is a laptop pane; ctrl+b then g picks Local"
  pause
  exit 0
fi

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
