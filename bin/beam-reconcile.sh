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
# already on the Beam, which is exactly the case we want to pick up. A profile
# whose label is not the current form (made by an older plugin version, or
# BEAM_LABEL_PREFIX changed) is renamed in place: no SSH, one herdr call.
registration_errors="$(mktemp)"
# Listing costs about 0.02 s locally (docs/measured.md); batch the refresh to
# avoid one extra process and full list parse per changed registration.
registrations_changed=0
trap 'rc=$?; rm -f "$registration_errors"; finish "$rc"' EXIT
while IFS=$'\t' read -r id uuid; do
  label="$(machine_label "$id")"
  pid="$(machine_id_for_uuid "$uuid")"
  if [ -n "$pid" ]; then
    old="$(machine_label_of "$pid")"
    if [ "$old" != "$label" ]; then
      # herdr 0.9.3 wants the profile id before --label; its --help shows the
      # other order and the parser rejects it (docs/measured.md).
      "$HERDR" machine rename "$pid" --label "$label" >/dev/null
      printf 'beams: relabelled %s as %s\n' "$old" "$label"
      MACHINES_JSON="$(jq --arg p "$pid" --arg l "$label" 'map(if .id == $p then .label = $l else . end)' <<<"$MACHINES_JSON")"
      export MACHINES_JSON
      registrations_changed=1
    fi
  else
    host="$(beam_host "$uuid")"
    if "$HERDR" machine add "ssh://$host" --label "$label" </dev/null >/dev/null 2>"$registration_errors"; then
      printf 'beams: added profile for %s as %s\n' "$id" "$label"
      registrations_changed=1
    else
      printf 'beams: could not register %s; check SSH access and install herdr on the existing Beam, then run bash bin/beam-reconcile.sh\n' "$id"
      cat "$registration_errors" >&2
      printf 'beams: install if missing: ssh %s %s\n' "$host" "'curl -fsSL https://herdr.dev/install.sh | sh'"
    fi
  fi
done < <(beams_json | jq -r '.[] | [.id, .uuid] | @tsv')

[ "$registrations_changed" = 0 ] || refresh_machines
save_state
