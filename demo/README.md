# Demo: a Beam, an agent, back to nothing

`demo/demo.sh` tells one of two stories. Each step prints the command it is about to
run, waits for Enter, runs it, and prints how long it took. The steps are numbered as
they run, so the numbers below are the ones the audience sees.

- **App story (7 steps, default).** An agent builds a small web app inside the Beam,
  starts it as a service, and you publish it as a Teleport application. Unattended
  (`DEMO_AUTO=1`) it takes about 52 s; paced with the talk track, plan on five minutes.
- **Task story (5 steps, `DEMO_PROMPT` set).** The same Beam and agent, running a task
  of your choosing as you, then the teardown. There is no service check or publish
  step, since the task may not serve anything.

The popup's title is the same for both; the script prints `Story: …` as its first
line, and `Task: …` with the first line of your prompt in the task story.

## Before you present

1. `TELEPORT_CLUSTER= tsh login --proxy=<tenant>.beams.sh`, and `tsh beams ls` works.
2. `BEAMS_PROXY` is set in `$(herdr plugin config-dir herdr-beams)/env`.
3. `tests/run.sh` is green.
4. One dry run: `DEMO_AUTO=1 demo/demo.sh`. It creates and removes a Beam, so the
   tenant, the model endpoint and your SSH config are all proven minutes before you
   start.
5. Open herdr with the sidebar visible and start the demo as a popup:

```sh
herdr plugin pane open --plugin herdr-beams --entrypoint demo
```

The pane is started by the running herdr, not by your shell, so variables exported in
the shell do not reach it. Pass each one with `--env`:

```sh
herdr plugin pane open --plugin herdr-beams --entrypoint demo --env DEMO_OPEN=1
```

| Variable | Effect |
|---|---|
| `DEMO_OPEN=1` | open the published URL in the browser |
| `DEMO_KEEP=1` | leave the Beam running at the end |
| `DEMO_AUTO=1` | no pauses (how the unit test runs it; also what happens when nobody is at the keyboard) |
| `DEMO_PROMPT` | the task story: this prompt goes to the agent instead of the app build |
| `DEMO_WORKSPACE` | the workspace label shown in the sidebar (`flask-app` for the app story, `task` otherwise) |

Running `demo/demo.sh` directly in a terminal takes the same variables the usual way,
`DEMO_AUTO=1 demo/demo.sh`.

If a step fails, the Beam the demo created is removed unless `DEMO_KEEP=1`, and the
popup stays open with the failure until you press a key. When the demo finishes, the
last screen also stays until a key is pressed.

## Talk track: the app story

Times are medians of three unattended runs on a `*.beams.sh` tenant, Teleport 18.11.2.

**1. Where we start (1 s).** The audience sees the Beam list and the machine list,
both empty. "Everything you are about to see is created from nothing and gone at the
end."

**2. Create a Beam, install herdr in it, add it to the sidebar (18 s).** "One command.
Teleport is provisioning a microVM with my identity delegated into it: a certificate
issued for the Beam, on my behalf, with a traceable link back to me. Watch the machine
list in the sidebar." When the entry appears: "That is a machine herdr can drive, with herdr
already running inside the sandbox. I never typed a password, never copied a key."

**3. Start the agent in the Beam and give it the task (9 s).** "I am starting the
agent (Claude Code here) inside the Beam from my laptop and handing it a task. Watch the agent list:
`working`." Then the point that lands: "There is no API key here. The Beam's
environment points the agent at an endpoint the tenant proxies. Usage is attributed to
me; there is nothing to leak."

**4. Wait for the agent to finish, then read what it did (18 s).** "The agent runs with
permission prompts off. The sandbox and Teleport's audit log are the guardrails, not
approval prompts." When the agent list flips to `done` (and, if system notifications
are on in herdr, the notification fires): "It wrote the app and started it with
`beamctl`, the Beam's own service manager, so the server outlives this shell." The
sub-step shows the agent's last lines.

**5. The app is a beam-init service, not a stray process (1 s).** "`beamctl list`: the
app is a supervised service." The sub-step: "`curl` inside the Beam answers with the
Beam's hostname."

**6. Publish port 8080 as a Teleport app (2 s).** "Port 8080 is now a Teleport
application URL. Only I can open it; every request is in the audit log." Open it.

**7. Tear it down (1 s).** "One command removes the Beam and its sidebar entry. Had I
walked away, it would have expired in 24 hours and the sidebar would have dropped it
the next time I opened a plugin pane."

Close: "A sandboxed agent with my identity and no secrets, in under a minute, and a
sidebar that shows me what every agent is doing. That is Beams plus herdr."

## Talk track: the task story

When the audience cares more about identity than about shipping an app, give the agent
an inventory of what it can reach as you:

```sh
herdr plugin pane open --plugin herdr-beams --entrypoint demo \
  --env DEMO_WORKSPACE=inventory \
  --env DEMO_PROMPT='Acting as me, list the SSH nodes you can reach with tsh, run one query
against postgres and one against mysql over VNet, and list the apps. Report a short
table. Do not probe other database engines and do not install anything.'
```

Steps 1 to 3 are the app story's. Then:

**4. Wait for the agent to finish, then read what it did (39 s, measured once).** "It
is listing nodes with `tsh`, querying two databases over VNet with a plain client, and
listing the apps, all as me." When the last lines appear: a table of nodes, databases
and apps, with your username in every `current_user` column. "Nothing on this machine
knows a password. The Beam holds a delegated identity, and the audit log shows every
one of those actions under my name and the Beam's."

**5. Tear it down (1 s).** As in the app story.

The prompt names its targets on purpose. The Beam's seeded notes already say which
database engines have no VNet path; an agent asked the open question "what can you
access" spent seven minutes timing out against five of them.

## What it needs

Everything the plugin needs (the [Requirements](../README.md#requirements) and
[Install](../README.md#install) sections of the top-level README): herdr, bash 4, a
logged-in `tsh`, the `tsh config` SSH block, `jq`, and `BEAMS_PROXY` in the plugin's
`env` file. The Beam image provides Python 3 with Flask, so the app story needs
nothing installed. The timings quoted above are from [docs/measured.md](../docs/measured.md).

## Recording

Not part of the repo. With asciinema installed (`brew install asciinema`), this records
an unattended run from the repo root:

```sh
asciinema rec -c 'DEMO_AUTO=1 demo/demo.sh' demo.cast
```

asciinema runs the `-c` string through `/bin/sh -c`, so the variable prefix works there.
