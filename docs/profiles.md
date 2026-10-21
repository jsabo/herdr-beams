# Agent profiles

[Back to the README](../README.md)

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
| `claude-opus` | Claude Code | `anthropic.claude-opus-5` | high | bypass | harness default |
| `claude-sonnet` | Claude Code | `anthropic.claude-sonnet-5` | medium | bypass | harness default |
| `codex-sol` | Codex | `openai.gpt-5.6-sol` | high | never | workspace-write |
| `codex-terra` | Codex | `openai.gpt-5.6-terra` | medium | on-request | workspace-write |

Bundled profiles use provider-qualified IDs advertised by compatible inference
catalogs. Short aliases can also be valid when explicitly configured by the proxy;
using a qualified ID does not prove which backend served a particular request.
Verify tenant-supported names with `tctl get app_servers` (requires appropriate
permissions), under each application's `spec.app.spec.inference.models`. A harness
picker alone is not evidence that the proxy serves every listed model.

These are examples for Claude Opus 5, Claude Sonnet 5, GPT-5.6 Sol and GPT-5.6 Terra.
Model IDs must match your Teleport inference proxy's aliases; their availability is
not guaranteed. The installed harness must support the selected model and flags.

Create `profiles.json` under `$(herdr plugin config-dir herdr-beams)` to replace a
bundled record or add a named profile. Records replace whole profiles; include every
required field. Installation and upgrades never rewrite this file. If you already
override a bundled profile, update its `model` field locally to adopt a new ID.
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

- Claude effort: `low`, `medium`, `high`, `max`. Approval: `default` (leave the
  harness's permission configuration intact) or `bypass`
  (`--dangerously-skip-permissions`).
- Codex effort: `minimal`, `low`, `medium`, `high`, `xhigh`, passed through
  `-c model_reasoning_effort="..."`. Approval: `default` (omit the flag),
  `on-request`, `untrusted`, or `never`, passed through `--ask-for-approval`.
  Sandbox: `read-only`, `workspace-write`, or `danger-full-access`, passed through
  `--sandbox`. `never` suppresses approval requests but retains the selected sandbox.
  With `workspace-write`, optional `network_access` accepts `true` or `false` and
  sets `-c sandbox_workspace_write.network_access=...`. Bundled Codex profiles
  enable networking for Teleport and repository access. Omitting the field in a
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
