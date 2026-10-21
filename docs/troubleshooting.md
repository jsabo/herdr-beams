# Troubleshooting

[Back to the README](../README.md)

- **The popup closed before you could read it.** A failing popup stays open with the
  reason and `beams: failed (exit N)` until a key is pressed. If you still see nothing,
  the popup never started: look for `plugin.pane.open` in
  `~/.config/herdr/herdr-server.log`.
- **A keybinding does nothing.** A `plugin_action` binding needs the plugin id
  (`herdr-beams.new`), not its name, and `herdr server reload-config` after editing the
  file. A `type = "shell"` binding runs through `/bin/sh -lc`, which reads
  `~/.profile`, not `~/.zshrc`; if `herdr` is not on that PATH, write its full path.
- **A keybinding does nothing while a Beam is selected in the sidebar.** herdr sends
  a plugin action to the selected machine's server, and the herdr on a Beam has no
  plugins (`herdr --machine beam/<id> plugin list` says so). Select Local, then press the
  chord, or run `herdr plugin action invoke herdr-beams.<id>` from a shell.
- **You cannot select text in a popup.** herdr captures the mouse for its own
  selection. Hold Shift while you drag; the terminal then selects natively and Cmd+C
  (or your terminal's copy key) takes it.
- **`cannot list Beams on <tenant>`.** tsh's own error is printed above it. The plugin
  only uses the tenant in `BEAMS_PROXY`; if you are not logged in:
  `TELEPORT_CLUSTER= tsh login --proxy=<tenant>.beams.sh` (the empty
  `TELEPORT_CLUSTER` matters when that variable is set in your shell).
- **`no Beam named <id>`.** The id is checked against `tsh beams ls` before anything
  runs. Beams have a short id (`neon-panel`) and a UUID; the popups take the short
  id.
- **`Beam <id> exists without a sidebar entry`.** The `new` popup failed after the
  Beam was created (SSH never came up, or the install failed). Remove it with the `rm`
  popup or `bash bin/beam-rm.sh <id>`, or fix the cause and run `bash bin/beam-reconcile.sh` from the plugin checkout
  if herdr is already installed on the Beam.
- **`plugin requires Herdr 0.9.1 or newer`** when linking or installing. The running
  herdr server is older than the binary. `herdr server stop` (this ends its panes),
  then start herdr again.
- **`ssh: … target host <id> is offline or does not exist`.** A Beam's SSH hostname
  is its UUID, not its short id. The plugin always uses the UUID; if you connect by
  hand, take it from `tsh beams ls -f json`.
- **`machine add` fails without a terminal.** herdr is not on the Beam yet. The `new`
  popup installs it; for a Beam created elsewhere, run
  `ssh beams@<uuid>.<tenant> 'curl -fsSL https://herdr.dev/install.sh | sh'` first.
- **`herdr: server shut down: server is shutting down`** when launching herdr. The
  client attached while an earlier server was still stopping. Run `herdr` again.
- **An `Action interrupted` toast** in the top right is herdr's own message for a
  server call that was cancelled, usually by Esc or a closed popup. The Beam and its
  agents are unaffected.
- **A direct chord does nothing, or resizes the window.** Most macOS terminals
  compose plain `alt` chords into a character before herdr sees them, and window
  managers such as Magnet take some `ctrl+alt` chords system-wide. The `prefix+`
  bindings above avoid both: only herdr sees the key after the prefix.
