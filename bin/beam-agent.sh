#!/usr/bin/env bash
# Start a coding agent inside a Beam from the laptop: a new workspace on the
# Beam's herdr server, the agent in its root pane, an optional first prompt.
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
# Usage: beam-agent.sh [beam-id] [workspace-label] [prompt...]
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
header "Start agent in a Beam"
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
  exec bash bin/beam-new.sh --agent
fi

id="$(pick_beam "${1:-}")"
machine="$(machine_label "$id")"
label="${2:-}"
shift $(( $# > 2 ? 2 : $# ))
prompt="$*"

if [ -z "$label" ] && interactive; then
  ask "Workspace label [work]: " label
fi
label="${label:-work}"

if [ -z "$prompt" ] && interactive; then
  ask "First prompt (empty for none): " prompt
fi

# The agent list (for the name) and the workspace are independent, and each
# is a round trip to the Beam's herdr, so both run at once.
taken_json="$(mktemp)"
"$HERDR" --machine "$machine" agent list > "$taken_json" &
list_pid=$!
created="$("$HERDR" --machine "$machine" workspace create --cwd '~' --label "$label" --no-focus)"
wait "$list_pid" || die "could not list the agents on $id"
pane="$(jq -r .result.root_pane.pane_id <<<"$created")"
phase "workspace $label on $id, pane $pane"

# Agent name: the kind, with a counter when that name is already taken here.
taken="$(jq -r '.result.agents[].name' "$taken_json")"
rm -f "$taken_json"
agent="$BEAM_AGENT_KIND"
n=2
while grep -qx "$agent" <<<"$taken"; do
  agent="$BEAM_AGENT_KIND-$n"
  n=$((n + 1))
done

# shellcheck disable=SC2086
"$HERDR" --machine "$machine" agent start "$agent" --kind "$BEAM_AGENT_KIND" --pane "$pane" -- $BEAM_AGENT_ARGS >/dev/null
phase "$BEAM_AGENT_KIND is ready as agent $agent"

if [ -n "$prompt" ]; then
  "$HERDR" --machine "$machine" agent prompt "$agent" "$prompt" >/dev/null
  phase "prompt sent; the agent list shows $agent as working"
fi

printf '\n'
card_open "$id · $label · $agent"
if [ -n "$prompt" ]; then
  card_line "$C_WARN$G_WAIT$C_RESET working · pane $pane"
else
  card_line "$C_OK$G_OK$C_RESET idle, waiting for a prompt · pane $pane"
fi
card_line "watch it:   herdr --machine $machine agent read $agent"
card_line "prompt it:  herdr --machine $machine agent prompt $agent \"...\" --wait"
card_close
pause
