#!/usr/bin/env bats
load '../helpers'

setup() { setup_fakes; }

# Every command the manifest declares must point at an existing, executable script.
@test "manifest: every declared command exists and is executable" {
  run grep -oE 'command = \["bash", "(bin|demo)/[a-z-]+\.sh"(, "[a-z-]+")?\]' herdr-plugin.toml
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 15 ]
  [ "${#lines[@]}" -eq "$(grep -c '^command = ' herdr-plugin.toml)" ]
  for line in "${lines[@]}"; do
    script="$(sed -E 's/.*"((bin|demo)\/[a-z-]+\.sh)".*/\1/' <<<"$line")"
    [ -x "$script" ] || { echo "not executable: $script"; return 1; }
  done
}

# Every pane has an action of the same id that opens it, so keybindings can be
# plugin_action bindings and `herdr plugin action invoke herdr-beams.<id>` works.
@test "manifest: every pane has an action with the same id, and both have a description" {
  mapfile -t panes < <(awk '/^\[\[panes\]\]/{p=1; next} /^\[\[/{p=0} p && /^id = /{gsub(/"/, "", $3); print $3}' herdr-plugin.toml)
  mapfile -t actions < <(awk '/^\[\[actions\]\]/{p=1; next} /^\[\[/{p=0} p && /^id = /{gsub(/"/, "", $3); print $3}' herdr-plugin.toml)
  [ "${#panes[@]}" -ge 7 ]
  [ "${panes[*]}" = "${actions[*]}" ]
  for id in "${panes[@]}"; do
    grep -q "\"bin/beam-open.sh\", \"$id\"" herdr-plugin.toml || { echo "action $id does not open its pane"; return 1; }
  done
  n_entries="$(grep -cE '^\[\[(panes|actions)\]\]' herdr-plugin.toml)"
  n_desc="$(grep -c '^description = ' herdr-plugin.toml)"
  [ "$n_desc" -eq $(( n_entries + 1 )) ]   # one per entry, plus the plugin's own
}

@test "manifest: every script in bin/ is declared, except the shared common.sh" {
  for script in bin/beam-*.sh; do
    grep -q "\"$script\"" herdr-plugin.toml || { echo "undeclared: $script"; return 1; }
  done
}

@test "manifest: required fields are present and the id is stable" {
  grep -q '^id = "herdr-beams"$' herdr-plugin.toml
  grep -qE '^version = "[0-9]+\.[0-9]+\.[0-9]+"$' herdr-plugin.toml
  grep -qE '^min_herdr_version = "[0-9]+\.[0-9]+\.[0-9]+"$' herdr-plugin.toml
  grep -q '^platforms = \[' herdr-plugin.toml
}

@test "manifest: min_herdr_version is the version the README asks for" {
  manifest="$(sed -nE 's/^min_herdr_version = "([0-9.]+)"$/\1/p' herdr-plugin.toml)"
  readme="$(grep -oE 'herdr [0-9]+\.[0-9]+\.[0-9]+ or newer' README.md | head -1 | awk '{print $2}')"
  [ -n "$manifest" ]
  [ "$manifest" = "$readme" ]
}

@test "manifest: interactive entries are popups, the reconcile hook is a startup hook" {
  run awk '/^\[\[panes\]\]/{p=1} p && /^placement/{print; p=0}' herdr-plugin.toml
  for line in "${lines[@]}"; do [ "$line" = 'placement = "popup"' ]; done
  grep -A1 '^\[\[startup\]\]' herdr-plugin.toml | grep -q 'beam-reconcile.sh'
}

@test "scripts: shellcheck and bash -n are clean" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  run shellcheck bin/*.sh demo/*.sh tests/fakes/* tests/run.sh
  [ "$status" -eq 0 ]
  run bash -n bin/*.sh demo/*.sh
  [ "$status" -eq 0 ]
}

@test "scripts: every script sources common.sh and enforces the config" {
  for script in bin/beam-*.sh; do
    grep -q '^\. bin/common.sh$' "$script" || { echo "$script does not source common.sh"; return 1; }
    case "$script" in
      bin/beam-reconcile.sh) ;;  # must stay quiet without config
      *) grep -q '^require_config$' "$script" || { echo "$script skips require_config"; return 1; } ;;
    esac
  done
}
