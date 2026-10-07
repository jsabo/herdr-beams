#!/usr/bin/env bash
# A paced, scripted demo: create a Beam, have a coding agent build and serve a
# small app inside it, publish it, tear it down. Every step prints the command
# it is about to run and waits for Enter.
#
#   DEMO_AUTO=1    no pauses (the unit test runs it this way; also the default
#                  when nobody is at the keyboard)
#   DEMO_OPEN=1    open the published URL in the browser (macOS `open`)
#   DEMO_KEEP=1    leave the Beam running at the end
#   DEMO_PROMPT    replace the task given to the agent; the app steps (service
#                  check, curl, publish) are skipped, since the task may not
#                  serve anything on 8080. Steps are numbered as they run, so
#                  the task story reads 1 to 5 and the app story 1 to 7.
#   DEMO_WORKSPACE the herdr workspace label for the agent (default: the
#                  story's name, flask-app or task)
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
quick_reconcile
interactive || DEMO_AUTO=1

DEMO_APP=1
if [ -n "${DEMO_PROMPT:-}" ]; then DEMO_APP=""; fi
DEMO_WORKSPACE="${DEMO_WORKSPACE:-${DEMO_APP:+flask-app}}"
DEMO_WORKSPACE="${DEMO_WORKSPACE:-task}"
DEMO_PROMPT="${DEMO_PROMPT:-Create /home/beams/demo/app.py: a Flask app listening on 0.0.0.0:8080. \
The page shows the title 'Hello from <hostname>' using socket.gethostname(), and a button that \
fetches /api/time (JSON with the current UTC time) and shows the result on the page. \
Start it as a beam-init service with: beamctl start --name web -- python3 /home/beams/demo/app.py \
Then verify with: curl -s localhost:8080 and curl -s localhost:8080/api/time \
When both work, reply with the single word: done}"

# The popup's header is the manifest title and does not follow a terminal
# title escape (checked on herdr 0.9.3), so the story names itself here.
if [ -n "$DEMO_APP" ]; then
  STORY="an agent builds and publishes an app"
else
  STORY="an agent runs your task as you"
fi
printf '\n%sStory: %s%s\n' "$C_BOLD" "$STORY" "$C_RESET"
if [ -z "$DEMO_APP" ]; then
  first="${DEMO_PROMPT%%$'\n'*}"
  printf 'Task: %s\n' "$(printf '%s' "$first" | cut -c1-100)"
fi

DEMO_START="$(now)"
N=0
# run_step "<heading>" "<what to show>" <command...>: show, wait for Enter, run, time it.
run_step() {
  local heading="$1" shown="$2" t0 rc=0
  shown="${shown//$HERDR/herdr}"
  printf '\n%s%s%s\n%s$ %s%s\n' "$C_BOLD" "$heading" "$C_RESET" "$C_ACCENT" "$shown" "$C_RESET"
  if [ "${DEMO_AUTO:-}" != 1 ]; then
    read -r -p '[enter] ' _ </dev/tty
  fi
  t0="$(now)"
  "${@:3}" || rc=$?
  printf '%s[%ss]%s\n' "$C_DIM" "$(awk -v s="$t0" -v n="$(now)" 'BEGIN { printf "%.1f", n - s }')" "$C_RESET"
  return "$rc"
}
# A numbered step, or an unnumbered sub-step, running a command.
step()    { N=$((N + 1)); run_step "$N. $1" "${*:2}" "${@:2}"; }
substep() { run_step "   $1" "${*:2}" "${@:2}"; }
# The same for a shell pipeline: shown as written, run with pipefail so a
# failure in any part fails the step. A third argument is what to show when
# the pipeline carries plumbing the audience need not see.
step_sh()    { N=$((N + 1)); run_step "$N. $1" "${3:-$2}" bash -eo pipefail -c "$2"; }
substep_sh() { run_step "   $1" "${3:-$2}" bash -eo pipefail -c "$2"; }

say() { printf '\n%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

# The Beam this demo created. beam-new prints "Beam <id> created" as soon as
# the Beam exists, so its output is the source: diffing the Beam list would
# pick up a Beam someone else created at the same moment.
id=""
NEW_OUT="$(mktemp)"
created_id() { sed -nE 's/^.*Beam ([a-z0-9-]+) created .*$/\1/p' "$NEW_OUT" | head -1; }
cleanup() {
  # A failure inside beam-new can leave a Beam behind before id is set.
  [ -n "$id" ] || id="$(created_id)"
  rm -f "$NEW_OUT"
  [ -n "$id" ] || return 0
  if [ "${DEMO_KEEP:-}" = 1 ]; then
    say "DEMO_KEEP=1: $id stays up; remove it later with: bash bin/beam-rm.sh $id"
    return 0
  fi
  say "tearing down $id"
  # beam-rm inherits this script's Beam cache, which may predate the Beam.
  refresh_beams 2>/dev/null || true
  bash bin/beam-rm.sh "$id" </dev/null || true
}
trap 'rc=$?; cleanup; finish $rc' EXIT

say "Teleport Beams + herdr. Watch the machine list in the sidebar and the agent list while this runs."

step_sh "Where we start: the Beams and Beam machines that exist now" \
  "tsh --proxy=$BEAMS_PROXY beams ls -f json | jq -r '.[].id'; $HERDR machine list --json | jq -r '.[].label'"
n_beams="$(beams_json | jq 'length')"
if [ "$n_beams" -eq 0 ]; then
  say "Nothing yet. Everything you are about to see is created from nothing and gone at the end."
else
  say "$n_beams Beam(s) already exist. The demo adds one more and removes only its own."
fi

step_sh "Create a Beam, install herdr in it, add it to the sidebar" \
  "bash bin/beam-new.sh </dev/null | tee '$NEW_OUT'" \
  "bash bin/beam-new.sh"
refresh_beams
refresh_machines
id="$(created_id)"
[ -n "$id" ] || die "beam-new did not report a new Beam"
machine="$(machine_label "$id")"
say "The machine list in the sidebar now shows $machine. Its herdr server is running inside the sandbox, with your delegated identity and the tenant's model endpoint."

step "Start $BEAM_AGENT_KIND in the Beam and give it the task" \
  bash bin/beam-agent.sh "$id" "$DEMO_WORKSPACE" "$DEMO_PROMPT" </dev/null
say "No API key was configured. The Beam's environment points the agent at the proxied endpoint, and it runs with permissions skipped: the sandbox and Teleport are the guardrails."

"$HERDR" --machine "$machine" agent wait "$BEAM_AGENT_KIND" --until working --timeout 20000 >/dev/null 2>&1 || true
wait_out="$(mktemp)"
step_sh "Wait for the agent to finish, then read what it did" \
  "$HERDR --machine '$machine' agent wait '$BEAM_AGENT_KIND' --timeout 600000 | tee '$wait_out'" \
  "$HERDR --machine $machine agent wait $BEAM_AGENT_KIND --timeout 600000" || true
state="$(jq -r '.result.agent.agent_status // empty' "$wait_out" 2>/dev/null || true)"
rm -f "$wait_out"
# 40 lines: Claude Code's input box takes the last dozen, a short answer sits above it.
substep "The agent's last lines" \
  "$HERDR" --machine "$machine" agent read "$BEAM_AGENT_KIND" --lines 40

case "$state" in
  done)
    say "The agent list went working, then done. Everything it reached, it reached as you: the Beam holds your delegated identity, nothing else." ;;
  blocked)
    say "The agent list shows blocked: it is waiting for an answer. Open its pane from the sidebar to see the question."
    DEMO_APP="" ;;
  *)
    say "The agent had not settled after ten minutes (state: ${state:-unknown}). Open its pane from the sidebar to see where it is."
    DEMO_APP="" ;;
esac

if [ -n "$DEMO_APP" ]; then
  say "It started the app with beamctl, the Beam's own service manager, so the app outlives any shell."

  step "The app is a beam-init service, not a stray process" \
    bash bin/beam-services.sh "$id" </dev/null
  host="$(beam_host "$(beam_uuid "$id")")"
  substep "It answers on port 8080 inside the Beam" \
    beam_ssh "$host" 'curl -s localhost:8080 | head -5; echo; curl -s localhost:8080/api/time'

  publish_out="$(mktemp)"
  step_sh "Publish port 8080 as a Teleport app" \
    "bash bin/beam-publish.sh '$id' http </dev/null | tee '$publish_out'" \
    "bash bin/beam-publish.sh $id http"
  url="$(grep -oE 'https://[^ ]+' "$publish_out" | head -1 || true)"
  rm -f "$publish_out"
  if [ -n "$url" ]; then
    say "Only you can open $url: it is a Teleport application, authenticated by your login, recorded in the audit log."
    if [ "${DEMO_OPEN:-}" = 1 ] && command -v open >/dev/null; then open "$url"; fi
  fi
elif [ "$state" = "done" ]; then
  say "DEMO_PROMPT was set, so the app steps (service check, port 8080, publish) are skipped."
fi
say "Audit, not scripted here: the Teleport audit log shows the SSH sessions into $id and every model call under your user."

if [ "${DEMO_KEEP:-}" = 1 ]; then
  say "DEMO_KEEP=1: leaving $id running."
else
  step "Tear it down: the Beam and its sidebar entry go together" \
    bash bin/beam-rm.sh "$id" </dev/null
  id=""
  : > "$NEW_OUT"   # so the exit handler does not find the id again
fi
say "Done in $(awk -v s="$DEMO_START" -v n="$(now)" 'BEGIN { printf "%.0f", n - s }') s."
pause
