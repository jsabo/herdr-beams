#!/usr/bin/env bash
# Start a coding agent inside a Beam: a new workspace on the Beam's herdr
# server, the agent in its root pane, an optional first prompt. Run from the
# laptop it drives the Beam's herdr with --machine; run on the Beam itself,
# which is what a keybinding pressed while that Beam is selected does, the same
# calls are local and there is no Beam to pick.
# The workspace is created without focus and the Beam's default "~" workspace
# keeps it: herdr clears an agent's `done` state as soon as its pane is viewed,
# and on a headless server the focused pane counts as viewed. An agent in the
# default workspace would go straight from working to idle, with no done state
# and no notification. Agents are named after their kind (claude, claude-2, ...)
# so the sidebar reads <beam> · <workspace> · claude.
# With no Beams at all and someone at the keyboard, creates one first (after
# asking, unless the pane was opened from a keybinding) and comes back here.
# Once the prompt is sent the pane is done: the agent list in the sidebar shows
# working, then done, and the agent's own pane is a click away, so this pane
# never waits on the agent.
# Usage, on the laptop: beam-agent.sh [--profile <name> | --pick-profile] [beam-id] [workspace-label] [prompt...]
# Usage, on a Beam:     beam-agent.sh [--profile <name> | --pick-profile] [workspace-label] [prompt...]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Start agent in a Beam"
# Internal handoff from beam-new, scoped to this invocation, never persisted.
prepared_harness=""
if [ "${1:-}" = --prepared-harness ]; then
  [ "$#" -ge 2 ] || die "--prepared-harness requires a harness"
  prepared_harness="$2"
  shift 2
fi
profile="${BEAM_AGENT_PROFILE:-}"
case "${1:-}" in
  --profile) [ "$#" -ge 2 ] || die "usage: beam-agent.sh --profile <name> [beam-id] [workspace] [prompt]"; profile="$2"; shift 2 ;;
  --pick-profile) pick_agent_profile; profile="$BEAM_AGENT_PROFILE"; shift ;;
esac
load_agent_profile "$profile"

if in_beam; then
  # On the Beam itself: this Beam, its own herdr, no Beam list and no SSH. An
  # empty machine selector is what makes every herdr_at call below local.
  id="$BEAM_SELF_ID"
  machine=""
  host=""
  label="${1:-}"
  shift $(( $# > 1 ? 1 : $# ))
else
  quick_reconcile

  if [ -z "${1:-}" ] && [ "$(beams_json | jq 'length')" -eq 0 ] && interactive; then
    off "no Beams on $BEAMS_PROXY"
    if must_confirm; then
      hints "enter create one and start the agent in it" "n close"
      yn=""
      ask "No Beams yet. Create one and start the agent in it? [Y/n] " yn
      case "$yn" in n|N) die "no Beams; create one with the New Beam pane" ;; esac
    fi
    # beam-new creates the Beam and hands back to this script with its id.
    exec bash bin/beam-new.sh --agent --profile "$profile" "${@:2}"
  fi

  id="$(pick_beam "${1:-}")"
  profile_id="$(machine_id "$id")"
  [ -n "$profile_id" ] || die "Beam $id has no sidebar entry; install herdr on it and run bash bin/beam-reconcile.sh"
  # A profile ID survives label changes and avoids ambiguous labels.
  machine="$profile_id"
  host="$(beam_host "$(beam_uuid "$id")")"
  label="${2:-}"
  shift $(( $# > 2 ? 2 : $# ))
fi
prompt="$*"

if [ -z "$label" ] && interactive; then
  ask "Workspace label [work]: " label
fi
label="${label:-work}"

if [ -z "$prompt" ] && interactive; then
  ask "First prompt (empty for none): " prompt
fi

if [ "$prepared_harness" != "$AGENT_KIND" ]; then
  busy "installing $AGENT_KIND integration on $id"
  install_agent_integration "$host" "$AGENT_KIND" \
    || die "could not install $AGENT_KIND integration on $id"
fi

if [ "$AGENT_KIND" = codex ]; then
  busy "registering the Herdr Codex hook on $id"
  trust_codex_integration "$host" \
    || die "could not prepare Codex hook trust on $id; no agent was launched"
fi

# The agent list (for the name), the workspace list (for the label) and the
# workspace itself are independent, and each is a round trip to the Beam's
# herdr, so all three run at once. The create cannot wait for the listing that
# decides its label without serialising two of them (docs/measured.md), so a
# label already in use is corrected by a rename below instead.
taken_json="$(mktemp)"
spaces_json="$(mktemp)"
list_pid=""
spaces_pid=""
cleanup_agent() {
  local rc="$?"
  trap - EXIT
  [ -z "$list_pid" ] || wait "$list_pid" || true
  [ -z "$spaces_pid" ] || wait "$spaces_pid" || true
  rm -f "$taken_json" "$spaces_json"
  finish "$rc"
  exit "$rc"
}
trap cleanup_agent EXIT
herdr_at "$machine" agent list > "$taken_json" &
list_pid=$!
herdr_at "$machine" workspace list > "$spaces_json" &
spaces_pid=$!
created="$(herdr_at "$machine" workspace create --cwd '~' --label "$label" --no-focus)"
wait "$list_pid" || die "could not list the agents on $id"
list_pid=""
wait "$spaces_pid" || die "could not list the workspaces on $id"
spaces_pid=""
pane="$(jq -ers '
  if length == 1 then
    .[0].result.root_pane.pane_id | select(type == "string" and length > 0)
  else empty end' <<<"$created")" \
  || die "workspace creation on $id returned no valid pane ID; inspect its workspaces before retrying"
jq -es 'length == 1 and (.[0].result.agents | type == "array" and all(.[]; .name | type == "string" and length > 0))' "$taken_json" >/dev/null \
  || die "invalid agent list on $id; workspace $label was created as pane $pane; inspect it before retrying"

# Two workspaces with the same label are indistinguishable in the sidebar, so a
# repeat takes the next free -<n>, the way the agent name does below. The
# workspace is renamed rather than created with the free label, because the
# listing that decides it arrives alongside the create. `workspace rename`
# takes the label positionally, unlike `machine rename` in beam-reconcile.sh.
workspace="$(jq -ers '
  if length == 1 then
    .[0].result.root_pane.workspace_id | select(type == "string" and length > 0)
  else empty end' <<<"$created")" \
  || die "workspace creation on $id returned no valid workspace ID; inspect its workspaces before retrying"
rename_pid=""
if [ -n "$(jq -r --arg l "$label" '.result.workspaces[]? | select(.label == $l) | .label' "$spaces_json")" ]; then
  taken_labels="$(jq -r '.result.workspaces[]?.label' "$spaces_json")"
  unique="$label"
  n=2
  while grep -qxF "$unique" <<<"$taken_labels"; do
    unique="$label-$n"
    n=$((n + 1))
  done
  herdr_at "$machine" workspace rename "$workspace" "$unique" >/dev/null 2>&1 &
  rename_pid=$!
  label="$unique"
fi
phase "workspace $label on $id, pane $pane"

# Agent name: the kind, with a counter when that name is already taken here.
taken="$(jq -r '.result.agents[].name' "$taken_json")"
rm -f "$taken_json"
agent="$AGENT_KIND"
n=2
while grep -qx "$agent" <<<"$taken"; do
  agent="$AGENT_KIND-$n"
  n=$((n + 1))
done

# Linux Node wrappers can expose only "MainThread" to process detection. Install
# a one-use shell shim in this fresh pane: only the actual Codex process inherits
# the hint, and the shim removes itself before running the executable.
#
# The shim also clears the pane, because Codex draws inline and would leave the
# shell prompt and the whole launch command above its own header, where Claude
# Code starts with a cleared screen (both read back with `pane read`,
# docs/measured.md). It has to be the escape sequence and not `clear`: a herdr
# pane runs with TERM=xterm-ghostty, which the Beam image has no terminfo entry
# for, so `clear` writes "unknown terminal type" instead of clearing.
if [ "$AGENT_KIND" = codex ]; then
  herdr_at "$machine" pane run "$pane" \
    'codex() { unset -f codex; printf "\033[H\033[2J\033[3J"; HERDR_AGENT=codex command codex "$@"; }' >/dev/null \
    || die "could not prepare Codex process detection in pane $pane; no agent was launched"
fi

herdr_at "$machine" agent start "$agent" --kind "$AGENT_KIND" --pane "$pane" -- "${AGENT_ARGS[@]}" >/dev/null
phase "$AGENT_KIND is ready as agent $agent"

# The harness's own name, for a sidebar row to show. A row template reads it as
# `{ token = "harness" }` (herdr resolves an unknown token name from the pane's
# reported tokens). Claude Code sets a terminal title herdr can show instead;
# Codex leaves the shell's, so without this its row has nothing where Claude's
# has a line. Display-only: a failure must not touch a running agent.
#
# The label and the first prompt are independent calls to the Beam's herdr, so
# they run at once (docs/measured.md: about 0.9 s each when forwarded).
case "$AGENT_KIND" in
  claude) harness="Claude Code" ;;
  codex)  harness="OpenAI Codex" ;;
  *)      harness="$AGENT_KIND" ;;
esac
herdr_at "$machine" pane report-metadata "$pane" \
  --source herdr-beams --token "harness=$harness" >/dev/null 2>&1 &
label_pid=$!

if [ -n "$prompt" ]; then
  herdr_at "$machine" agent prompt "$agent" "$prompt" >/dev/null
  phase "prompt sent; the agent list shows $agent as working"
fi

wait "$label_pid" || off "could not label $agent as $harness in the sidebar"
[ -z "$rename_pid" ] || wait "$rename_pid" || off "workspace $label kept the label it was created with"

printf '\n'
card_open "$id · $label · $agent"
if [ -n "$prompt" ]; then
  card_line "$C_WARN$G_WAIT$C_RESET working · pane $pane"
else
  card_line "$C_OK$G_OK$C_RESET idle, waiting for a prompt · pane $pane"
fi
card_line "watch it:   $(herdr_cmd "$machine") agent read $agent"
card_line "prompt it:  $(herdr_cmd "$machine") agent prompt $agent \"...\" --wait"
card_close
pause
