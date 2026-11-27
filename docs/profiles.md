# Agent profiles

[Back to the README](../README.md)

The README's [configuration guide](../README.md#configuration) explains what to
create and where. This reference covers profile fields and runtime behavior.
Bundled profiles live at `profiles/defaults.json` inside the installed plugin;
your optional `profiles.json` lives beside `env` in the directory returned by
`herdr plugin config-dir herdr-beams`. Both configuration files are user-created;
installation supplies the bundled profiles and preserves user configuration.

## Supported harnesses

The profile loader supports `claude` (Claude Code) and `codex`. These agents come
preinstalled in the current Beam image. Beams can also run other agent harnesses,
such as Pi, installed inside the runtime. Configure those agents for the tenant's
inference endpoints and launch them from a shell in the Beam. Installing a harness
does not automatically add profile support or herdr agent-state integration.

Use `herdr plugin action invoke herdr-beams.profiles` to choose a profile in a
popup. The existing `agent` entry keeps its legacy behavior unless
`BEAM_AGENT_PROFILE` is set. For a direct hotkey, use `command = "herdr-beams.claude"`
or `command = "herdr-beams.codex"` with `type = "plugin_action"`. These open the
usual Beam/workspace/prompt popup without a profile question.

Bundled examples in [profiles/defaults.json](../profiles/defaults.json):

| Profile | Harness | Example model ID | Effort | Approval | Sandbox |
|---|---|---|---|---|---|
| `claude-opus` | Claude Code | `anthropic.claude-opus-5-5` | high | default (ask) | harness default |
| `claude-sonnet` | Claude Code | `anthropic.claude-sonnet-5` | medium | default (ask) | harness default |
| `codex-sol` | Codex | `openai.gpt-6.1-sol` | high | on-request | workspace-write |
| `codex-terra` | Codex | `openai.gpt-6.1-terra` | medium | on-request | workspace-write |

Bundled profiles use provider-qualified IDs, and only models every Beams tenant
is provisioned with. A tenant can offer more (one measured tenant also served
`openai.gpt-6.2-sol`); the model picker shows them.

## The tenant's model catalog

A Beam reaches models through the tenant's Teleport inference apps. The app whose
`spec.inference.format` is `anthropic` serves Claude Code; the one whose format is
`openai` serves Codex. Each app accepts only the names in its
`spec.inference.models`, ignoring case, and refuses any other name unless it sets
`fallback_model`. Each model usually appears twice there, as a short name
(`gpt-6.2-sol`) and as its provider-qualified name (`openai.gpt-6.2-sol`); both work.

The plugin reads those lists with `tsh --proxy=<tenant> apps ls -f json`. That
needs no admin rights: the standard Beams user role grants the inference apps. It
caches the result as `models.json` in the plugin's state directory, refreshes it in
the startup hook, and uses it three ways:

- **Picker.** The profile list marks a profile whose model the cached catalog no
  longer offers with `· model not offered`. After the profile question, `profiles`
  lists one name per model for that harness, preferring the provider-qualified
  name. It marks the profile's model, and marks `· new` on a model the tenant added
  in the last seven days. The cache records when each name first appeared; the
  first listing for a tenant is the baseline, so nothing in it counts as new.
  Enter keeps the profile's model; a number replaces only the model for this
  launch. A profile model the tenant no longer offers is flagged, and Enter then
  cancels. The
  question is skipped when the list cannot be read, when the app accepts any name,
  and when the profile's model is the only one offered. The listing runs while the
  profile question is open, so the model question shows the current list.
- **Launch check.** Every profile launch (`agent` with a profile, `profiles`,
  `claude`, `codex`, and `new` before it creates a Beam) checks the model against
  the cache. A miss is checked once more against a fresh listing, then refused
  with the names on offer. A name the app would route to its `fallback_model`
  launches with a warning naming the model that will answer.
- **`--model <id>`.** `beam-agent.sh` and `beam-new.sh` accept it after the profile
  flag. It replaces the profile's model for one launch and is checked the same way.

The listing works on the laptop and inside a Beam under its delegated identity
(docs/measured.md). When no listing is possible (not logged in, or a tenant whose
roles do not grant the apps), launches go ahead unchecked and print that they did.
The legacy unprofiled launch is checked too, when `BEAM_AGENT_ARGS` names a model
with `--model <id>`, `--model=<id>`, or for Codex `-m <id>`; its refusal says to
change that line in `env` or set `BEAM_AGENT_PROFILE`.

Claude Code adds a second list of its own. The Beam image's `~/.claude/settings.json`
sets `availableModels`, and Claude Code replaces any other model with an allowed one,
printing `Model "<name>" is restricted by your organization's settings. Using <model>
instead.` A model the tenant's app serves but that list omits therefore runs as a
different model. Read the agent's header to confirm which model answered.

The check covers what the proxy accepts, not what the harness supports. Codex
can be pointed at non-OpenAI models the `openai` app serves (such as `zai.glm-5`)
and may lack catalog metadata for them; see
[troubleshooting](troubleshooting.md). Using a qualified ID does not prove which
backend served a particular request.

Create `profiles.json` under `$(herdr plugin config-dir herdr-beams)` to replace a
bundled record or add a named profile. Records replace whole profiles; include every
required field. Installation and upgrades never rewrite this file. If you already
override a bundled profile, update its `model` field locally to adopt a new ID; a
launch check names the replacement when the old one is withdrawn.
For example:

```json
{
  "claude-opus": {
    "harness": "claude",
    "model": "your-proxy-opus-alias",
    "effort": "high",
    "approval": "default"
  },
  "review": {
    "harness": "codex",
    "model": "your-proxy-codex-alias",
    "effort": "high",
    "approval": "on-request",
    "sandbox": "read-only"
  }
}
```

Profile names use lowercase letters, digits and hyphens, starting with a letter.
Each record requires `harness`, a nonempty `model`, `effort`, and `approval`.
Codex also requires `sandbox`; Claude profiles must omit it. Unknown fields,
unsupported values, malformed JSON and control characters in model IDs fail before
any Beam or workspace is created.

- Claude effort: `low`, `medium`, `high`, `max`. Approval: `default` (select the
  harness's normal permission mode via `--permission-mode default`) or `bypass`
  (`--dangerously-skip-permissions`).
- Codex effort: `minimal`, `low`, `medium`, `high`, `xhigh`, passed through
  `-c model_reasoning_effort="..."`. Approval: `default` (omit the flag),
  `on-request`, `untrusted`, or `never`, passed through `--ask-for-approval`.
  Sandbox: `read-only`, `workspace-write`, or `danger-full-access`, passed through
  `--sandbox`. `never` suppresses approval requests but retains the selected sandbox.
  With `workspace-write`, optional `network_access` accepts `true` or `false` and
  sets `-c sandbox_workspace_write.network_access=...`. Bundled Codex profiles
  disable networking by default. Set it to `true` in a custom profile for Teleport
  and repository access. Omitting the field in a
  custom profile preserves Codex's configured network policy. Claude profiles and
  other sandbox modes must omit this field.

Set defaults in the plugin's `env` file:

```sh
BEAM_AGENT_PROFILE=review               # optional default for agent/new
BEAM_CLAUDE_PROFILE=claude-sonnet        # default: claude-opus
BEAM_CODEX_PROFILE=codex-sol             # default: codex-sol
```

An explicit `--profile` or picker selection wins over `BEAM_AGENT_PROFILE` and
replaces legacy harness arguments for that launch. Without a profile,
`BEAM_AGENT_KIND` and `BEAM_AGENT_ARGS` retain their defaults and whitespace-separated
argument behavior (shell quotes inside the string are not parsed). Profile model
strings are passed as single arguments, with no shell evaluation or glob expansion.

```sh
bash bin/beam-agent.sh --profile claude-opus <beam> implementation "Build the API"
bash bin/beam-agent.sh --profile codex-sol <beam> review "Review the API"
```

Each launch creates a separate unfocused Herdr workspace, chooses an unused agent
name (`claude`, `codex`, `codex-2`, ...), and installs that harness's integration
before starting it. Claude Code and Codex can remain active on the same Beam.
The plugin does not coordinate agents, create Git worktrees, or isolate their files;
use distinct working directories or agree on file ownership yourself. Simultaneous
launch requests for the same harness are not locked and can race for an agent name.
Selected profiles and supplied workspace/prompt arguments survive the popup flow
that first creates a Beam. Profile approval prompts may require opening the agent's
pane; the launch popup does not wait for the agent. Harness binaries come from the
Beam image and are not installed by the profile loader.

Codex setup trusts only the installed Herdr `SessionStart` command through Codex's
app-server API, using Codex's reported hash and config writer. It does not bypass
hook trust globally. Other untrusted hooks can still require manual review.
The installed Codex must expose `hooks/list` and `config/batchWrite`; an unsupported
API or unwritable config stops setup before workspace creation.

Bundled Claude profiles explicitly use normal permission mode, not permission
bypass. This mode is not network isolation: existing tool allow rules and sandbox
settings still apply. The Codex network switch restricts sandboxed agent commands;
model inference still needs connectivity. Existing sessions keep their settings.

For step-by-step file creation, copyable Claude/Codex YOLO profiles, and selecting
defaults for each action, see the README's [Configuration](../README.md#configuration).
YOLO examples use new names, so bundled prompt-based choices remain available.

The legacy unprofiled `agent` action still uses `BEAM_AGENT_ARGS` from `env`. Set
`BEAM_AGENT_PROFILE=claude-opus` there to use the bundled prompt-based profile;
existing explicit permission-bypass settings are not rewritten by updates.
