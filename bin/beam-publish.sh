#!/usr/bin/env bash
# Publish whatever listens on port 8080 in a Beam as a Teleport app. Run on the
# Beam itself, which is where a keybinding pressed while that Beam is selected
# runs, it publishes that Beam.
# Usage, on the laptop: beam-publish.sh [beam-id] [http|tcp]
# Usage, on a Beam:     beam-publish.sh [http|tcp]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Publish port 8080"

if in_beam; then
  id="$BEAM_SELF_ID"
  kind="${1:-}"
else
  quick_reconcile
  id="$(pick_beam "${1:-}")"
  kind="${2:-}"
fi
if [ -z "$kind" ] && interactive; then
  ask "Protocol on port 8080, http or tcp [http]: " kind
fi
kind="${kind:-http}"

case "$kind" in
  http) busy "publishing port 8080 of $id over HTTPS"; publish_args=("$id") ;;
  tcp)  busy "publishing port 8080 of $id as plain TCP"; publish_args=(--tcp "$id") ;;
  *)    die "protocol must be http or tcp" ;;
esac
if ! tshb publish "${publish_args[@]}"; then
  # A Beam's delegated identity cannot reissue certificates, and what that
  # forbids is not fully mapped; the laptop's own login always works.
  ! in_beam || note "if tsh refused the identity, publish from the laptop with Local selected"
  die "could not publish port 8080 of $id"
fi
ok "published; only your Teleport login can open it, every request is audited"
pause
