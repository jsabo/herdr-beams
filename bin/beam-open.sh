#!/usr/bin/env bash
# Open one of this plugin's popup panes. Every [[actions]] entry in the
# manifest runs this with the pane id, so a keybinding can be a plugin_action
# (command = "herdr-beams.<id>") instead of a shell command that has to find
# herdr on /bin/sh's PATH. Runs without a terminal and returns at once.
# The pane is opened with BEAMS_YES=1: the chord or the invoke was the
# decision, so the pane skips its y/N question and acts (see must_confirm
# in common.sh). The plugin menu opens panes without it and still asks.
# Usage: beam-open.sh <pane-id>
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config

pane="${1:-}"
[ -n "$pane" ] || die "usage: beam-open.sh <pane-id>"
grep -q "^id = \"$pane\"\$" herdr-plugin.toml || die "no pane named $pane in herdr-plugin.toml"

exec "$HERDR" plugin pane open --plugin herdr-beams --entrypoint "$pane" --env BEAMS_YES=1
