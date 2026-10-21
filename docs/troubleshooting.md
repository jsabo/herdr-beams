# Troubleshooting

[Back to the README](../README.md)

- **`mapfile: command not found` or `ids: unbound variable`.** An older plugin is
  running with macOS system Bash 3.2. Update the plugin and install modern Bash
  with `brew install bash`. Current versions automatically switch to Bash 4+ from
  PATH or either standard Homebrew prefix. Custom installations must put their
  Bash on herdr’s PATH.

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

- **`plugin ... is already linked from a local path`.** Update the linked checkout,
  or uninstall the link and install from GitHub. Keep the configuration directory.
  See [local-link updates](../README.md#updating-a-locally-linked-plugin).
- **Beam deletion fails.** The plugin leaves the runtime's sidebar entry in place.
  Check the `tsh` error and `tsh beams ls` before retrying. Remove-all stops at the
  failed Beam and saves earlier successful deletions.
- **`could not register <id>`.** The original Herdr error follows the message.
  Check SSH access and the Herdr installation on that existing Beam, then run
  `bash bin/beam-reconcile.sh` from the checkout. Registration failures can also be
  caused by authentication, networking or version compatibility; they do not prove
  Herdr is missing.

- **Codex waits for hook review or agent startup times out.** Update the plugin.
  Current versions register trust for the installed Herdr `SessionStart` hook
  before starting Codex. If an existing session skipped this hook, exit that Codex
  session and launch again after updating. Other hooks still need their own review.
  If setup reports an unsupported API, update Codex in the Beam; if config is
  unwritable, correct its permissions. Do not keep launching duplicate agents.
- **Codex `tsh` commands fail with `socket: operation not permitted`.** Codex's
  network sandbox can block DNS even while the Beam itself is connected. The
  bundled Codex profiles enable network access while keeping `workspace-write`.
  Custom profiles must explicitly set `"network_access": true` with that sandbox
  if they need networking; approval `never` alone does not enable it.
- **Codex reports missing model metadata.** A model alias can return responses
  without a matching Codex catalog entry. Check that the configured inference
  endpoint and installed Codex expose metadata for your selected alias. The plugin
  does not invent model capabilities or change aliases automatically.

- **Codex opens but is absent from Agents, and startup times out.** If
  `herdr --machine beam/<id> pane process-info --pane <pane-id>` shows a Node
  wrapper named `MainThread`, update the plugin. New launches set Herdr's
  process hint only for Codex, using a one-use Bash function in the new pane;
  the function removes itself before starting Codex. Existing sessions must be
  exited and relaunched. This does not change model routing or repair unrelated
  SSH disconnects. Check `pane list` and `agent list` after relaunch.
