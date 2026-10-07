# shellcheck shell=bash
# Sourced by every script in bin/ and by demo/demo.sh. Resolves the herdr
# binary, the plugin directories and the Beams tenant, caches the two lists
# every script needs, and provides the helpers they share.
set -euo pipefail

HERDR="${HERDR_BIN_PATH:-herdr}"
# Defaults match where herdr puts them (src/plugin_paths.rs), for running the
# scripts by hand outside a plugin invocation.
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/plugins/herdr-beams}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins/config/herdr-beams}"
mkdir -p "$STATE_DIR" "$CONFIG_DIR"

# User settings. BEAMS_PROXY is the only required one.
if [ -f "$CONFIG_DIR/env" ]; then
  # shellcheck disable=SC1091
  . "$CONFIG_DIR/env"
fi
BEAMS_PROXY="${BEAMS_PROXY:-}"
BEAMS_TENANT="${BEAMS_PROXY%%:*}"
BEAM_LOGIN="${BEAM_LOGIN:-beams}"
BEAM_AGENT_KIND="${BEAM_AGENT_KIND:-claude}"
BEAM_AGENT_ARGS="${BEAM_AGENT_ARGS:---dangerously-skip-permissions}"

# ---- look -----------------------------------------------------------------
#
# Colour only when stdout is a terminal and NO_COLOR is unset, so a scripted
# call, an agent reading the output, and the unit tests all see plain text.
# The glyphs are the ones herdr's own sidebar uses for agent state.

# shellcheck disable=SC2034  # C_ACCENT is used by demo/demo.sh, which sources this file
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_RESET=$'\033[0m'
  C_OK=$'\033[32m' C_WARN=$'\033[33m' C_ERR=$'\033[31m' C_ACCENT=$'\033[36m'
else
  # shellcheck disable=SC2034
  C_BOLD="" C_DIM="" C_RESET="" C_OK="" C_WARN="" C_ERR="" C_ACCENT=""
fi
G_OK="●" G_WAIT="◐" G_OFF="○" G_ERR="✗" G_DONE="✓"

# header "<pane title>": the first line of every pane. The popup frame already
# shows the manifest title, so this line adds the tenant the pane acts on.
header() {
  printf '%sTeleport Beams%s · %s %s· %s%s\n\n' \
    "$C_BOLD" "$C_RESET" "$1" "$C_DIM" "${BEAMS_PROXY:-no tenant configured}" "$C_RESET"
}

# One status line each: ok (green dot), busy (half dot), off (hollow dot),
# bad (red cross), note (dim). The text stays plain so tests can match it.
ok()   { printf '%s%s%s %s\n' "$C_OK" "$G_OK" "$C_RESET" "$*"; }
busy() { printf '%s%s%s %s\n' "$C_WARN" "$G_WAIT" "$C_RESET" "$*"; }
off()  { printf '%s%s%s %s\n' "$C_DIM" "$G_OFF" "$C_RESET" "$*"; }
bad()  { printf '%s%s%s %s\n' "$C_ERR" "$G_ERR" "$C_RESET" "$*" >&2; }
note() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

# A card for one Beam, in the style of a herdr sidebar entry: a titled top
# edge, one line per fact, a bottom edge. The right edge is left open, so no
# column arithmetic is needed and a long line simply runs on.
#   card_open "<title>"; card_line "<text>"...; card_close
card_open()  { printf '%s╭─%s %s%s%s %s──────────────────────────────%s\n' "$C_DIM" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "$C_DIM" "$C_RESET"; }
card_line()  { printf '%s│%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
card_close() { printf '%s╰─────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }

# A shell command the user can copy: dim prompt, plain command.
show_cmd() { printf '%s$%s %s\n' "$C_DIM" "$C_RESET" "$*"; }

# The key hints on the last line of a pane, Captain's-Deck style:
#   hints "y confirm" "n keep"  ->  y confirm · n keep
hints() {
  local sep="" h
  printf '%s' "$C_DIM"
  for h in "$@"; do printf '%s%s' "$sep" "$h"; sep=" · "; done
  printf '%s\n' "$C_RESET"
}

# ---- timing ---------------------------------------------------------------

now() { printf '%s' "${EPOCHREALTIME:-$SECONDS}"; }
SCRIPT_START="$(now)"
elapsed() { awk -v s="$SCRIPT_START" -v n="$(now)" 'BEGIN { printf "%.1f", n - s }'; }
# phase "<what just finished>": a tick, the time since the script began, the fact.
phase() { printf '%s%s%s %s[+%5ss]%s %s\n' "$C_OK" "$G_DONE" "$C_RESET" "$C_DIM" "$(elapsed)" "$C_RESET" "$*"; }

# ---- small helpers --------------------------------------------------------

die() { printf '%s%s%s beams: %s\n' "$C_ERR" "$G_ERR" "$C_RESET" "$*" >&2; exit 1; }

# "in 2h 14m" / "in 3d" / "expired", from an ISO-8601 expiry. Works with GNU
# and BSD date; falls back to an empty string when neither parses it.
expires_in() {
  local iso="${1%%.*}" t n d
  iso="${iso%Z}"
  t="$(date -u -d "${iso}Z" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%S' "$iso" +%s 2>/dev/null)" || return 0
  n="$(date -u +%s)"
  d=$(( t - n ))
  if   [ "$d" -le 0 ]; then printf 'expired'
  elif [ "$d" -ge 172800 ]; then printf 'in %dd' $(( d / 86400 ))
  else printf 'in %dh %02dm' $(( d / 3600 )) $(( d % 3600 / 60 ))
  fi
}

# True when someone is at the keyboard: a popup pane, or a terminal. The unit
# tests set BEAMS_INTERACTIVE=1 and feed answers on stdin.
interactive() { [ "${BEAMS_INTERACTIVE:-}" = 1 ] || [ -t 0 ]; }

# True when a y/N question should be asked before acting. A keybinding or
# `herdr plugin action invoke` opens a pane through beam-open.sh, which sets
# BEAMS_YES=1: pressing the chord was the decision, so the pane acts at once.
# The plugin menu and a bare `herdr plugin pane open` still ask. The env file
# is sourced above, after the environment, so BEAMS_YES=0 in it wins over the
# action's --env and brings the questions back for keybindings too; remove the
# line to turn them off again. Questions that collect a value (a label, a
# prompt, a protocol) are not confirmations and do not use this.
must_confirm() { interactive && [ "${BEAMS_YES:-}" != 1 ]; }

# ask "<prompt>" <var> and ask_key "<prompt>" <var> read an answer. The prompt
# is printed by hand so it shows whatever stdin is, and end-of-file leaves
# the variable empty instead of ending the script.
ask()     { printf '%s' "$1"; read -r "$2" || true; }
ask_key() { printf '%s' "$1"; read -r -n1 "$2" || true; printf '\n'; }

pause() {
  if interactive; then
    printf '\n%spress any key to close%s ' "$C_DIM" "$C_RESET"
    read -r -n1 -s || true
    printf '\n'
  fi
}

# Runs on every exit. A popup closes with its process, so a failure would
# vanish before anyone could read it: keep the pane open until a key is
# pressed. FAIL_HINT is what a script wants said if it dies part way through.
#
# Ctrl+C is the way out of a popup, not a failure. Without the INT trap bash
# would run this with status 0 when Ctrl+C lands on a question or a foreground
# call, and the hint about a half-made Beam would vanish with the popup
# (measured, docs/measured.md). With it every Ctrl+C arrives here as 130: the
# popup closes at once, unless FAIL_HINT is set, and then it stays until a key
# is pressed.
FAIL_HINT=""
finish() {
  local rc="$1"
  [ "$rc" -ne 0 ] || return 0
  [ -z "$FAIL_HINT" ] || printf '%s%s%s beams: %s\n' "$C_ERR" "$G_ERR" "$C_RESET" "$FAIL_HINT" >&2
  if [ "$rc" -eq 130 ]; then
    [ -n "$FAIL_HINT" ] || return 0
    if interactive; then
      printf '%sbeams: cancelled%s\n' "$C_DIM" "$C_RESET" >&2
      pause
    fi
    return 0
  fi
  if interactive; then
    printf '%s%s beams: failed (exit %s)%s\n' "$C_ERR" "$G_ERR" "$rc" "$C_RESET" >&2
    pause
  fi
}
trap 'finish $?' EXIT
trap 'exit 130' INT

require_config() {
  [ -n "$BEAMS_PROXY" ] || die "set BEAMS_PROXY=<tenant>.beams.sh in $CONFIG_DIR/env"
}

tshb() { tsh --proxy="$BEAMS_PROXY" beams "$@"; }

# The plugin's own ssh calls share one connection per Beam for a minute, so a
# readiness probe, an install and a service listing cost one Teleport session.
SSH_OPTS=(-o BatchMode=yes -o ControlMaster=auto -o ControlPath=/tmp/herdr-beams-%C -o ControlPersist=60)
# shellcheck disable=SC2029  # the remote command is passed through as given
beam_ssh() { ssh "${SSH_OPTS[@]}" "$@"; }

# ---- the two lists, fetched once per script run ---------------------------
#
# BEAMS_JSON and MACHINES_JSON are exported so helpers called inside command
# substitutions see them. Scripts call load_lists (or quick_reconcile, which
# calls it) once at the top; after a change they call refresh_* or patch the
# cache directly.

load_lists() {
  if [ -z "${BEAMS_JSON:-}" ]; then
    # tsh's own message (not logged in, wrong proxy, no network) comes first.
    BEAMS_JSON="$(tshb ls -f json)" \
      || die "cannot list Beams on $BEAMS_PROXY; if you are not logged in: TELEPORT_CLUSTER= tsh login --proxy=$BEAMS_PROXY"
    export BEAMS_JSON
  fi
  if [ -z "${MACHINES_JSON:-}" ]; then
    MACHINES_JSON="$("$HERDR" machine list --json)"
    export MACHINES_JSON
  fi
}
refresh_beams() { BEAMS_JSON="$(tshb ls -f json)"; export BEAMS_JSON; }
refresh_machines() { MACHINES_JSON="$("$HERDR" machine list --json)"; export MACHINES_JSON; }

beams_json() { load_lists; printf '%s' "$BEAMS_JSON"; }
machines_json() { load_lists; printf '%s' "$MACHINES_JSON"; }

# Patch the Beam cache after tsh beams add / rm, without another round trip.
remember_beam() { BEAMS_JSON="$(jq --argjson n "$1" '. + [$n]' <<<"$(beams_json)")"; export BEAMS_JSON; }
forget_beam() { BEAMS_JSON="$(jq --arg id "$1" 'map(select(.id != $id))' <<<"$(beams_json)")"; export BEAMS_JSON; }

# Record the Beams that exist, for status and for diagnosing a failed run.
save_state() { beams_json > "$STATE_DIR/beams.json"; }

beam_uuid() { beams_json | jq -er --arg id "$1" '.[] | select(.id == $id) | .uuid'; }

beam_host() { printf '%s@%s.%s' "$BEAM_LOGIN" "$1" "$BEAMS_TENANT"; }

# herdr profile id for a Beam id (profiles are labelled with the Beam id).
machine_id() { machines_json | jq -r --arg l "$1" '.[] | select(.label == $l) | .id'; }

# Profiles that point at this tenant: id, target, label.
beam_machines_tsv() {
  machines_json | jq -r --arg t ".$BEAMS_TENANT" \
    '.[] | select(.target | endswith($t)) | [.id, .target, .label] | @tsv'
}

# Beam id of the machine currently selected in the sidebar, if it is a Beam.
selected_beam() {
  machines_json | jq -r --arg t ".$BEAMS_TENANT" \
    '.[] | select(.selected and (.target | endswith($t))) | .label'
}

# Drop sidebar entries whose Beam has expired or been deleted. Uses only the
# two cached lists: no SSH, no adds, so every pane can afford it on entry.
quick_reconcile() {
  load_lists
  local live pid target label uuid changed=0
  live="$(beams_json | jq -r '.[].uuid')"
  while IFS=$'\t' read -r pid target label; do
    uuid="${target#ssh://*@}"
    uuid="${uuid%%.*}"
    if ! grep -qx "$uuid" <<<"$live"; then
      off "$label is gone; dropping it from the sidebar"
      "$HERDR" machine remove "$pid" >/dev/null
      changed=1
    fi
  done < <(beam_machines_tsv)
  [ "$changed" = 0 ] || refresh_machines
}

# Resolve which Beam to act on: explicit argument (checked against the list),
# then the selected machine, then the only Beam, otherwise ask.
pick_beam() {
  local wanted="${1:-}" ids sel
  if [ -n "$wanted" ]; then
    beam_uuid "$wanted" >/dev/null 2>&1 || die "no Beam named $wanted; tsh beams ls shows the ids"
    printf '%s' "$wanted"
    return
  fi
  sel="$(selected_beam)"
  if [ -n "$sel" ]; then printf '%s' "$sel"; return; fi
  mapfile -t ids < <(beams_json | jq -r '.[].id')
  case "${#ids[@]}" in
    0) die "no Beams; create one with the New Beam pane" ;;
    1) printf '%s' "${ids[0]}" ;;
    *)
      interactive || die "several Beams and none selected; pass a Beam id"
      PS3='Beam: '
      select sel in "${ids[@]}"; do
        [ -n "$sel" ] && { printf '%s' "$sel"; return; }
      done
      die "no Beam chosen"
      ;;
  esac
}

# Wait until the Beam accepts SSH (a new Beam needs a few seconds). The first
# success also opens the shared connection the next calls reuse.
wait_for_ssh() {
  local host="$1" i
  for i in $(seq 1 60); do
    beam_ssh -o ConnectTimeout=5 "$host" true >/dev/null 2>&1 && return 0
    sleep 1
  done
  die "$host did not accept SSH after $i attempts"
}

# What an agent inside a Beam otherwise spends minutes rediscovering. The
# Beam's own ~/.claude/CLAUDE.md and ~/AGENTS.md cover the environment
# variables and the VNet naming; this adds the facts they leave out.
beam_notes() {
  cat <<'EOF'

## Inside a Beam (added by herdr-beams)

- `tsh` holds a delegated identity that cannot reissue certificates. `tsh db connect`,
  `tsh db login`, `tsh proxy db`, `tsh proxy app` and `tsh kube login` fail with
  "identity is not allowed to reissue certificates". That is by design: do not retry
  them and do not run `tsh login`.
- Databases are reached only over VNet, with a plain client, and only for postgres,
  mysql, sql-server and cockroachdb. Other engines (mongodb, redis, oracle, cassandra,
  clickhouse) resolve to the public proxy and hang. Do not probe them.
- The database user is the full Teleport username from `tsh status`. A connection
  URI cannot carry the `@` in it, so pass the user separately:
    psql "host=<db>.db.$TELEPORT_CLUSTER dbname=<name> user=<teleport user> sslmode=disable"
    mysql -h <db>.db.$TELEPORT_CLUSTER -u '<teleport user>'
- Not installed: mysql, kubectl, mongosh, redis-cli, docker. apt works
  (`mariadb-client` gives a mysql client); it has no mongosh, cqlsh,
  clickhouse-client or sqlplus.
- `tsh ssh <login>@<node>` works for the nodes and logins your roles allow.
- The identity is renewed in the background for the life of the Beam. `tsh status`
  shows about an hour of validity at any time; that is not a deadline.
EOF
}

# Install herdr on the Beam if it is missing, plus the agent integration so
# herdr sees the agent's state, and seed the notes above once. One SSH
# session does all of it: the notes arrive on stdin. Idempotent. Prints the
# remote herdr version.
prepare_beam() {
  local host="$1"
  # shellcheck disable=SC2016  # $HOME is meant to expand on the Beam
  beam_notes | beam_ssh "$host" '
    set -e
    notes="$(cat)"
    if ! command -v herdr >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/herdr" ]; then
      curl -fsSL https://herdr.dev/install.sh | sh >/dev/null
    fi
    "$HOME/.local/bin/herdr" integration install '"$BEAM_AGENT_KIND"' >/dev/null
    mkdir -p "$HOME/.claude"
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/AGENTS.md"; do
      grep -qs "^## Inside a Beam" "$f" || printf "%s\n" "$notes" >> "$f"
    done
    "$HOME/.local/bin/herdr" --version
  '
}
