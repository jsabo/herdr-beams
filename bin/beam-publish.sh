#!/usr/bin/env bash
# Publish whatever listens on port 8080 in a Beam as a Teleport app.
# Usage: beam-publish.sh [beam-id] [http|tcp]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Publish port 8080"
quick_reconcile

id="$(pick_beam "${1:-}")"
kind="${2:-}"
if [ -z "$kind" ] && interactive; then
  ask "Protocol on port 8080, http or tcp [http]: " kind
fi
kind="${kind:-http}"

case "$kind" in
  http) busy "publishing port 8080 of $id over HTTPS"; tshb publish "$id" ;;
  tcp)  busy "publishing port 8080 of $id as plain TCP"; tshb publish --tcp "$id" ;;
  *)    die "protocol must be http or tcp" ;;
esac
ok "published; only your Teleport login can open it, every request is audited"
pause
