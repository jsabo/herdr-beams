#!/usr/bin/env bash
# Make the Beams keybindings work while a Beam is the selected machine, for a
# Beam that already exists. `new` does this for every Beam it creates; this
# pane is for the ones created before plugin 0.9.0, or after an uninstall.
#
# It installs this plugin on the Beam, writes the plugin's settings there, and
# appends config/beam-keys.toml to the Beam's own herdr config. The Beam's herdr
# server is already running with the old config, so it is told to reload: that
# is what republishes the command list the client builds its keymap from.
# Usage: beam-keys.sh [beam-id]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Beam keybindings"
laptop_only "the Beam keybindings pane"
quick_reconcile

id="$(pick_beam "${1:-}")"
uuid="$(beam_uuid "$id")"
host="$(beam_host "$uuid")"
machine="$(machine_id "$id")"

busy "installing the plugin and its keys on $id"
install_beam_keys "$host" "$id" "$uuid" >/dev/null \
  || die "could not install the plugin on $id; check SSH access and that herdr is on the Beam"
phase "plugin, settings and key block in place on $id"

if [ -n "$machine" ]; then
  busy "reloading the Beam's herdr config so it republishes its keys"
  "$HERDR" --machine "$machine" server reload-config >/dev/null \
    || die "the keys are on $id but its herdr did not reload; switch to another machine and back, or restart its server"
  phase "$id republished its command list"
else
  off "$id has no sidebar entry yet; its herdr will read the keys when one is added"
fi

printf '\n'
card_open "$id"
card_line "$C_OK$G_OK$C_RESET the Beams keys work while $id is selected"
card_line "ctrl+b then shift and the initial: C)laude O)penAI A)gent"
card_line "S)tatus L)ogs E)xpose · B)eam K)ill Q)uit are laptop only"
card_close
printf '\n'
note "new Beam, delete and delete-all stay on the laptop; ctrl+b then g picks Local"
hints "ctrl+b ? lists the keys herdr has live for the selected machine"
pause
