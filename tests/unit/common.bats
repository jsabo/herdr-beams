#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

# Source common.sh in a subshell and call one of its functions.
common() { run bash -c ". bin/common.sh; $1" </dev/null; }

@test "require_config fails with a clear message when BEAMS_PROXY is unset" {
  : > "$HERDR_PLUGIN_CONFIG_DIR/env"
  common "require_config"
  [ "$status" -eq 1 ]
  [[ "$output" == *"set BEAMS_PROXY="* ]]
}

@test "tenant is derived from BEAMS_PROXY without a port" {
  printf 'BEAMS_PROXY=example.beams.sh:443\n' > "$HERDR_PLUGIN_CONFIG_DIR/env"
  common 'printf "%s" "$BEAMS_TENANT"'
  [ "$output" = "example.beams.sh" ]
}

@test "beam_host is <login>@<uuid>.<tenant>" {
  common 'beam_host aaaaaaaa-0000-4000-8000-000000000001'
  [ "$output" = "beams@aaaaaaaa-0000-4000-8000-000000000001.example.beams.sh" ]
}

@test "beam_uuid looks the Beam up by id" {
  common 'beam_uuid beta-two'
  [ "$output" = "bbbbbbbb-0000-4000-8000-000000000002" ]
}

@test "beam_uuid fails for an unknown Beam" {
  common 'beam_uuid nope'
  [ "$status" -ne 0 ]
}

@test "the Beam list is fetched once per run, however often it is read" {
  common 'beams_json >/dev/null; beam_uuid alpha-one >/dev/null; pick_beam beta-two >/dev/null; machine_id alpha-one >/dev/null; selected_beam >/dev/null'
  [ "$status" -eq 0 ]
  [ "$(call_count 'beams ls -f json')" -eq 1 ]
  [ "$(call_count 'herdr machine list --json')" -eq 1 ]
}

@test "remember_beam and forget_beam patch the cache without another tsh call" {
  common 'load_lists; remember_beam "$(cat "$FAKE_STATE/add.json")"; beams_json | jq -r ".[].id"; forget_beam alpha-one; beams_json | jq -r ".[].id"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"new-beam"* ]]
  [ "$(printf '%s\n' "$output" | grep -c alpha-one)" -eq 1 ]
  [ "$(call_count 'beams ls -f json')" -eq 1 ]
}

@test "beams_json shows tsh's own error, then how to log in" {
  touch "$FAKE_STATE/not-logged-in"
  common 'beams_json'
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: not logged in"*"TELEPORT_CLUSTER= tsh login --proxy=example.beams.sh"* ]]
}

@test "a failure keeps the popup open until a key is pressed when someone is at the keyboard" {
  run_interactive beam-agent.sh nope api <<<"x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"*"failed (exit 1)"*"press any key to close"* ]]
}

@test "a failure does not wait for a key without a terminal" {
  run_script beam-agent.sh nope api
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"* ]]
  [[ "$output" != *"press any key"* ]]
  [[ "$output" != *"failed (exit"* ]]
}

@test "Ctrl+C closes the popup at once and is not reported as a failure" {
  # SIGINT to the script itself: the INT trap turns it into exit 130.
  run env BEAMS_INTERACTIVE=1 bash -c '. bin/common.sh; kill -INT $$; echo "not reached"' <<<""
  [ "$status" -eq 130 ]
  [[ "$output" != *"not reached"* ]]
  [[ "$output" != *"failed (exit"* ]]
  [[ "$output" != *"cancelled"* ]]
  [[ "$output" != *"press any key"* ]]
}

@test "Ctrl+C after a Beam was created keeps the hint on screen until a key is pressed" {
  run env BEAMS_INTERACTIVE=1 bash -c '. bin/common.sh; FAIL_HINT="Beam x exists without a sidebar entry"; kill -INT $$' <<<"x"
  [ "$status" -eq 130 ]
  [[ "$output" == *"Beam x exists without a sidebar entry"*"beams: cancelled"*"press any key to close"* ]]
  [[ "$output" != *"failed (exit"* ]]
}

@test "Ctrl+C without a terminal leaves nothing waiting" {
  run bash -c '. bin/common.sh; FAIL_HINT="Beam x exists without a sidebar entry"; kill -INT $$' </dev/null
  [ "$status" -eq 130 ]
  [[ "$output" == *"Beam x exists without a sidebar entry"* ]]
  [[ "$output" != *"press any key"* ]]
}

@test "success never pauses on exit by itself" {
  run_interactive beam-publish.sh alpha-one http </dev/null
  [ "$status" -eq 0 ]
  # exactly the one pause the script asks for, none from the exit handler
  [ "$(printf '%s' "$output" | grep -c "press any key")" -eq 1 ]
  [[ "$output" != *"failed (exit"* ]]
}

@test "quick_reconcile drops the profile of a Beam that is gone and nothing else" {
  common 'quick_reconcile; machines_json | jq -r ".[].label"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone-beam is gone"* ]]
  [[ "$output" == *"alpha-one"* ]]
  [[ "$output" == *"workbox"* ]]
  [[ "$output" != *$'\ngone-beam\n'* ]]
  grep -q "^herdr machine remove id-gone-beam$" "$FAKE_LOG"
  ! grep -q "machine remove id-alpha-one" "$FAKE_LOG"
  ! grep -q "machine remove id-workbox" "$FAKE_LOG"
}

@test "quick_reconcile never adds and never uses ssh" {
  common 'quick_reconcile'
  [ "$status" -eq 0 ]
  ! grep -q "machine add" "$FAKE_LOG"
  ! grep -q "^ssh" "$FAKE_LOG"
}

@test "quick_reconcile refreshes the machine cache only when it removed something" {
  common 'quick_reconcile; quick_reconcile'
  [ "$status" -eq 0 ]
  [ "$(call_count 'herdr machine list --json')" -eq 2 ]
  jq 'map(select(.label != "gone-beam"))' "$REPO/tests/fixtures/machines.json" > "$FAKE_STATE/machines.json"
  : > "$FAKE_LOG"
  common 'quick_reconcile; quick_reconcile'
  [ "$(call_count 'herdr machine list --json')" -eq 1 ]
}

@test "pick_beam honours an explicit argument" {
  common 'pick_beam beta-two'
  [ "$output" = "beta-two" ]
}

@test "pick_beam rejects an unknown explicit id" {
  common 'pick_beam nope'
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam named nope"* ]]
}

@test "pick_beam offers a menu when several Beams and someone is at the keyboard" {
  run env BEAMS_INTERACTIVE=1 bash -c '. bin/common.sh; pick_beam' <<<"2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1) alpha-one"*"2) beta-two"* ]]
  [[ "$output" == *"beta-two" ]]
}

@test "pick_beam treats an abandoned menu as a failure, not an empty id" {
  run env BEAMS_INTERACTIVE=1 bash -c '. bin/common.sh; pick_beam' </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beam chosen"* ]]
}

@test "pick_beam uses the machine selected in the sidebar" {
  select_machine alpha-one
  common 'pick_beam'
  [ "$output" = "alpha-one" ]
}

@test "pick_beam ignores a selected machine that is not a Beam" {
  select_machine workbox
  jq 'map(select(.id == "alpha-one"))' "$FAKE_STATE/beams.json" > "$FAKE_STATE/b.tmp" && mv "$FAKE_STATE/b.tmp" "$FAKE_STATE/beams.json"
  common 'pick_beam'
  [ "$output" = "alpha-one" ]
}

@test "pick_beam takes the only Beam when nothing is selected" {
  jq 'map(select(.id == "beta-two"))' "$FAKE_STATE/beams.json" > "$FAKE_STATE/b.tmp" && mv "$FAKE_STATE/b.tmp" "$FAKE_STATE/beams.json"
  common 'pick_beam'
  [ "$output" = "beta-two" ]
}

@test "pick_beam refuses to guess between several Beams without a terminal" {
  common 'pick_beam'
  [ "$status" -eq 1 ]
  [[ "$output" == *"several Beams"* ]]
}

@test "pick_beam fails when there are no Beams" {
  printf '[]' > "$FAKE_STATE/beams.json"
  common 'pick_beam'
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Beams"* ]]
}

@test "machine_id maps a Beam id to its herdr profile id" {
  common 'machine_id alpha-one'
  [ "$output" = "id-alpha-one" ]
  common 'machine_id beta-two'
  [ -z "$output" ]
}

@test "phase prints the elapsed time and the text" {
  common 'phase "hello"'
  [[ "$output" =~ ^✓\ \[\+\ *[0-9.]+s\]\ hello$ ]]
}

# ---- look: colour only on a terminal, glyphs and cards as plain text ----------

@test "look: no escape codes reach a pipe, an agent or a test" {
  run_script beam-status.sh
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
  run_interactive beam-rm.sh alpha-one <<<"n"
  [[ "$output" != *$'\033'* ]]
}

@test "look: NO_COLOR is honoured even on a terminal" {
  run env NO_COLOR=1 bash -c '. bin/common.sh; printf "%s|%s|%s" "$C_BOLD" "$C_OK" "$C_RESET"' </dev/null
  [ "$output" = "||" ]
}

@test "look: a card has a titled top edge, prefixed lines and a bottom edge" {
  common 'card_open neon-panel; card_line "one"; card_line "two"; card_close'
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "╭─ neon-panel ─"* ]]
  [ "${lines[1]}" = "│ one" ]
  [ "${lines[2]}" = "│ two" ]
  [[ "${lines[3]}" == "╰─"* ]]
}

@test "look: status lines carry the sidebar glyphs, hints join with a middle dot" {
  common 'ok up; busy starting; off gone; note aside; hints "y yes" "n no"; show_cmd herdr machine list'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "● up" ]
  [ "${lines[1]}" = "◐ starting" ]
  [ "${lines[2]}" = "○ gone" ]
  [ "${lines[3]}" = "aside" ]
  [ "${lines[4]}" = "y yes · n no" ]
  [ "${lines[5]}" = '$ herdr machine list' ]
}

@test "look: phase ticks, die crosses" {
  common 'phase "SSH up"; die "no such Beam"'
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "✓ [+"*"s] SSH up" ]]
  [[ "$output" == *"✗ beams: no such Beam"* ]]
}

# A time a given number of seconds from now, as the ISO-8601 string tsh prints.
iso_from_now() {
  local t=$(( $(date -u +%s) + $1 ))
  date -u -d "@$t" +%Y-%m-%dT%H:%M:%S.000000000Z 2>/dev/null || date -u -r "$t" +%Y-%m-%dT%H:%M:%S.000000000Z
}

@test "expires_in: expired, hours and minutes, or whole days" {
  common 'expires_in 2000-01-01T00:00:00.000000000Z'
  [ "$output" = "expired" ]
  common "expires_in $(iso_from_now 5400)"
  [[ "$output" == "in 1h 29m" || "$output" == "in 1h 30m" ]]
  common "expires_in $(iso_from_now 300000)"
  [ "$output" = "in 3d" ]
  common 'expires_in not-a-date'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
