# Claude Code in Docker Sandboxes

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside a
[Docker Sandbox](https://docs.docker.com/ai/sandboxes/): a microVM with its own
kernel, filesystem, and Docker Engine. Outbound traffic goes through a host-side
proxy with a deny-by-default network policy, and API keys are injected by that
proxy, so they never enter the VM.

Written against the Docker Sandboxes documentation (`sbx` CLI) as of October 2026.

> **Status:** not tested yet — `sbx` is not installed on this machine. Commands
> and files follow Docker's documentation; check them on the first run.

> **Note:** guides from 2025 use `docker sandbox run claude`. That is the
> container-based Docker Desktop version, now deprecated. This repository uses the
> standalone `sbx` CLI, which does not need Docker Desktop.

## Files

| File                         | Purpose                                                        |
| ---------------------------- | -------------------------------------------------------------- |
| [`setup.sh`](setup.sh)       | One-time hardening: global settings and the network policy     |
| [`sbxenv.yaml`](sbxenv.yaml) | Experimental environment file: clone mode, resources, env vars |

There is no Dockerfile: Claude Code comes as a built-in template,
`docker/sandbox-templates:claude-code`.

## Requirements

- macOS 14 (Sonoma) or later on Apple silicon, Windows 11 with the Windows
  Hypervisor Platform, or Ubuntu 24.04+ with KVM
- A Docker account (`sbx login` signs in with Docker OAuth)
- For Claude: a Claude subscription (Max, Team, or Enterprise) **or** an Anthropic
  API key. Unlike OpenShell, subscription login works here.

## Installation

```sh
brew trust docker/tap
brew install docker/tap/sbx
sbx login
```

## Setup

### 1. Harden settings and set the network policy

Run [`setup.sh`](setup.sh) once, after `sbx login` and **before the first
`sbx run`** — otherwise the first run asks you to choose a network preset.

```sh
bash setup.sh
```

It does the following, globally for all sandboxes:

- `ssh.agentForwardingEnabled false` — forwarding is on by default and lets the
  agent sign git pushes and SSH logins with your host keys.
- `browser.enabled false` — a URL opened in your host browser reaches any site,
  outside the network policy.
- `skills.defaultMode off` — no shared skills store that one sandbox could change
  for others.
- `policy init deny-all` — the Locked Down preset: nothing is allowed until you
  allow it.
- `allow network api.anthropic.com` — the Anthropic API.
- `deny network http-intake.logs.us5.datadoghq.com` — Claude Code telemetry. Deny
  rules win over allow rules, including rules added by kits.

Optional rules for package registries and GitHub are commented out in the script.

The **Balanced** preset (Docker's recommendation) blocks by default but allows a
baseline of AI APIs, package managers, code hosts, registries, and cloud services
— including broad patterns such as `*.googleapis.com`. Use it if Locked Down is too
strict: `sbx policy reset`, then `sbx policy init balanced`.

### 2. Give Claude credentials

Either sign in with your subscription inside the sandbox — run `/login` in Claude
Code; the session token stays on the host — or store an API key:

```sh
sbx secret set anthropic   # prompts for the key
```

The sandbox only sees a placeholder; see
[Secrets and environment variables](#secrets-and-environment-variables).

## Usage

Claude Code runs as `claude --dangerously-skip-permissions` by default: it does not
ask before running commands. The sandbox is the security boundary.

Host-level Claude configuration (`~/.claude`) is not used. Project-level files in
the workspace (`CLAUDE.md`, `.claude/settings.json`) are.

### Clone mode (recommended)

The agent works on a private clone inside the sandbox; your repository is mounted
read-only at `/run/sandbox/source`. Nothing reaches your working tree until you
fetch it:

```sh
cd ~/Code/my-project
sbx run --clone --name my-project claude .

# on the host, while the sandbox is running:
git fetch sandbox-my-project
git diff main..sandbox-my-project/<branch>
git checkout -b <branch> sandbox-my-project/<branch>
```

The `sandbox-<name>` remote is added to your repository's Git config and is
reachable only while the sandbox runs. Clone mode is fixed when the sandbox is
created, and `sbx rm` deletes the clone — fetch what you want to keep first.

### Direct mode (default)

Without `--clone`, the current directory is mounted **read-write**: the agent edits
your working tree live and can change anything in it, including hidden files,
build scripts, and Git hooks.

```sh
cd ~/Code/my-project
sbx run --name my-project claude
```

After a session, review more than `git diff`: Git hooks live in `.git/hooks` and do
not show up in it, and `package.json` scripts, `Makefile`, and CI configs run
outside the sandbox later.

### Without a workspace

`sbx create` without a path mounts nothing. The agent works in
`/home/agent/workspace`; copy files in and out with `sbx cp`:

```sh
sbx create --name scratch claude
sbx cp ./src/ scratch:/home/agent/workspace/src
sbx run --name scratch
sbx cp scratch:/home/agent/workspace/output.log ./
```

### Pass arguments to Claude

Everything after `--` goes to Claude Code. Arguments starting with `-` are added
after the defaults; a bare word (such as `agents`) replaces them, which drops
`--dangerously-skip-permissions`.

```sh
sbx run --name my-project claude -- "Add error handling to the login function"
sbx run --name my-project -- -c   # claude --dangerously-skip-permissions -c
```

### Environment file (experimental)

[`sbxenv.yaml`](sbxenv.yaml) describes the sandbox declaratively: clone mode,
CPU and memory, environment variables, and no shared skills. The project path is
passed as an argument, so the file stays outside the project it mounts and the
agent cannot change it:

```sh
cd ~/Code/my-project
sbx env plan ~/Code/personal/docker-sandbox-claude --env-arg project=$PWD
sbx env run  ~/Code/personal/docker-sandbox-claude --env-arg project=$PWD
```

`plan` shows the changes without applying them. The sandbox is named
`claude-<project-folder>`. Workspace and `sandboxOptions` apply only at creation;
to change them, run `sbx env rm` with the same arguments and create it again.
Network rules are not part of the file; they stay in `sbx policy`.

### Reattach and persistence

Sandboxes keep running after the agent exits, and keep installed packages,
images, and history across `sbx stop`. Reattach with `sbx run --name my-project`
from any directory, or run `sbx` with no arguments to open the dashboard
(`Enter` attaches, `x` opens a shell, `s` starts or stops, `r` removes). `sbx rm`
deletes the VM and everything in it; your host files are not touched.

## Useful commands

### Sandboxes

| Task                                 | Command                                              |
| ------------------------------------ | ---------------------------------------------------- |
| Open the dashboard                   | `sbx`                                                |
| List sandboxes                       | `sbx ls`                                             |
| Start or reattach                    | `sbx run --name my-project`                          |
| Open a shell                         | `sbx exec -it my-project bash`                       |
| Copy files into the sandbox          | `sbx cp ./file my-project:/home/agent/workspace/`    |
| Copy files out                       | `sbx cp my-project:/home/agent/workspace/out.log ./` |
| Publish a port                       | `sbx ports my-project --publish 8080:3000`           |
| Stop, keeping its state              | `sbx stop my-project`                                |
| Remove                               | `sbx rm my-project`                                  |
| Remove all stopped sandboxes         | `sbx prune`                                          |
| Remove the sandbox when Claude exits | `sbx run --rm claude`                                |
| Save a sandbox as a template         | `sbx template save my-project my-template:v1`        |

### Network rules

Rules are global unless you add `--sandbox <name>`; deny rules win over allow
rules. Unlike OpenShell, a rule applies to the whole sandbox, not to a specific
program in it.

| Task                              | Command                                                                    |
| --------------------------------- | -------------------------------------------------------------------------- |
| List active rules                 | `sbx policy ls --wide`                                                     |
| List the rules a kit added        | `sbx policy ls my-project --source kit --wide`                             |
| Allow hosts                       | `sbx policy allow network "pypi.org,files.pythonhosted.org"`               |
| Allow for one sandbox only        | `sbx policy allow network --sandbox my-project api.example.com`            |
| Allow only some methods and paths | `sbx policy allow network api.github.com --method GET --path '/repos/**'`  |
| Deny a host or request            | `sbx policy deny network api.example.com --method POST --path '/admin/**'` |
| Remove a rule                     | `sbx policy rm network --resource api.example.com`                         |
| Check whether a host is allowed   | `sbx policy check network api.example.com`                                 |
| See blocked requests              | `sbx policy log`                                                           |
| List pending approval requests    | `sbx policy approval ls`                                                   |
| Answer them                       | `sbx policy approval respond`                                              |
| Start over with another preset    | `sbx policy reset`                                                         |

An approval applies to later requests, not the one that was blocked, so ask
Claude to retry afterwards. Treat a request to a host you do not recognize as a
sign of prompt injection and reject it. Kits can add allow rules even under Locked
Down; review them with `sbx policy ls --source kit`. Outbound UDP and ICMP are
blocked.

#### WebSearch is not covered by the network policy

Claude's WebSearch tool runs on Anthropic's servers, and its results come back
through `api.anthropic.com`, so the network policy cannot block it (verified in the
OpenShell setup). Search results are untrusted content, and therefore a possible
source of prompt injection. To turn WebSearch off, add a deny rule to Claude
Code's managed settings inside the sandbox:

```sh
sbx exec my-project sudo mkdir -p /etc/claude-code
echo '{"permissions":{"deny":["WebSearch"]}}' \
  | sbx exec -i my-project sudo tee /etc/claude-code/managed-settings.json
```

Restart the Claude session afterwards. The file survives `sbx stop`, not `sbx rm`.
This is a guardrail, not a security boundary: the agent has `sudo` inside the VM
and could remove it.

### Settings

| Task                        | Command                                       |
| --------------------------- | --------------------------------------------- |
| List settings               | `sbx settings ls`                             |
| Show one value              | `sbx settings get ssh.agentForwardingEnabled` |
| Change a value              | `sbx settings set <key> <value>`              |
| Back to the default         | `sbx settings unset <key>`                    |
| Apply settings that need it | `sbx daemon restart`                          |

## Secrets and environment variables

| Kind                                        | How                                                              | Agent sees the real value? |
| ------------------------------------------- | ---------------------------------------------------------------- | -------------------------- |
| Plain settings (`DEBUG=1`, a region, a URL) | `sbx run -e KEY=VALUE`, `--env-file`, or `env:` in `sbxenv.yaml` | Yes                        |
| Secrets (API keys, tokens)                  | `sbx secret set` / `sbx secret set-custom`                       | No — only a placeholder    |

Never put secrets in `-e`, env files, or the workspace. `-e NAME` without a value
copies it from your shell. To set a variable for every later session, append an
`export` line to `/etc/sandbox-persistent.sh` inside the sandbox.

### How secrets are hidden

Secrets are stored on the host. For each service, the host-side proxy adds the
credential to outbound HTTP **headers**, and only for that service's hosts.
Inside the sandbox the variable holds a placeholder (`proxy-managed`, or
`sbx-cs-<random>` for custom secrets). Do not set API keys inside the sandbox
yourself; the agents are already configured for the proxy.

| Task                                   | Command                                           |
| -------------------------------------- | ------------------------------------------------- |
| Store a secret (prompts for the value) | `sbx secret set anthropic`                        |
| Store the output of a host command     | `sbx secret set github --command 'gh auth token'` |
| Import from your shell's env variables | `sbx secret import --dry-run`, then without it    |
| Only for one sandbox                   | `sbx secret set anthropic --sandbox my-project`   |
| List                                   | `sbx secret ls`                                   |
| Remove                                 | `sbx secret rm github`                            |

`--command` and `--ref` (1Password or AWS Secrets Manager) resolve the value when
needed and cache it for 55 minutes (`--refresh` changes that). Avoid `--value`: it
puts the secret in your shell history.

Built-in services include `anthropic`, `github`, `openai`, `google`, `openrouter`,
and others. `anthropic` is sent to `api.anthropic.com`, `console.anthropic.com`,
`claude.ai`, and `mcp-proxy.anthropic.com`.

### Add a secret for another service (experimental)

```sh
sbx secret set-custom \
  --host api.example.com \
  --env MY_API_TOKEN \
  --command 'op read op://Private/Example/token'
```

Repeat `--host` for more domains (`*` matches one label, `**` any number). The
placeholder is replaced only in request headers, not in bodies. The host also
needs a network allow rule.

### GitHub

```sh
sbx secret set github   # paste a fine-grained token
sbx policy allow network "github.com,api.github.com"
sbx policy deny network api.github.com --method POST --path '/gists'
```

The `github` secret is sent to `api.github.com`, `github.com`,
`raw.githubusercontent.com`, `gist.github.com`, and the Copilot hosts. Prefer a
**fine-grained token** limited to the repositories Claude needs, without Gists
permission, over `--command 'gh auth token'`, which hands over your full `gh` login.
With clone mode you may not need a token at all: fetch the agent's branches from
the host and push from there.

### Limits

- **An endpoint that echoes requests back leaks the secret.** An allowed host that
  returns request headers (an echo service, a debug endpoint) gives the agent the
  real value. Allow only the hosts that need the secret, and use least-privilege
  tokens.
- **Only HTTP header authentication can be hidden.** SSH keys, database passwords
  over raw TCP, and secrets used locally need the real value inside the sandbox.
- **On Linux without a Secret Service,** secrets are stored in a file that any
  process running as your user can read.
- `sbx reset` deletes all stored secrets.

## Differences from the OpenShell setup

|                        | OpenShell                                  | Docker Sandboxes                                  |
| ---------------------- | ------------------------------------------ | ------------------------------------------------- |
| Isolation              | Container (or microVM) with Landlock rules | microVM per sandbox, own kernel and Docker Engine |
| Claude Code image      | You build it                               | Built-in template                                 |
| Project files          | Uploaded copy                              | Read-write mount (default), clone, or none        |
| Network rules          | YAML, per program, live updates            | `sbx policy`, by host/method/path                 |
| Filesystem rules       | Read-only system paths, fixed at start     | Agent has `sudo` inside the VM                    |
| Claude permissions     | Prompts by default                         | `--dangerously-skip-permissions` by default       |
| Subscription login     | No, API key only                           | Yes, `/login`                                     |
| Secrets                | Headers, query, path                       | Headers only                                      |
| Extra channels to host | None by default                            | SSH agent and host browser, on by default         |

`setup.sh` turns off the SSH agent and host browser access.

## Troubleshooting

- **A request is blocked.** Run `sbx policy log`, allow the host with
  `sbx policy allow network <host>`, and retry. If the rule has no effect, your
  organization may manage policies centrally; those take precedence.
- **API key errors.** Check `sbx secret ls`, and do not set `ANTHROPIC_API_KEY`
  inside the sandbox — the proxy replaces it on the way out.
- **Docker login expired.** Run `sbx login`.
- **Kit or startup problems.** Run with `sbx -D run ...` to stream the logs, or read
  `/var/log/sbx-kit-startup.log` with `sbx exec`.
- **Anything else.** `sbx daemon restart`, then `sbx diagnose`.

## References

- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
- [Install](https://docs.docker.com/ai/sandboxes/install/) and
  [Get started](https://docs.docker.com/ai/sandboxes/get-started/)
- [Claude Code agent](https://docs.docker.com/ai/sandboxes/agents/claude-code/)
- [Usage](https://docs.docker.com/ai/sandboxes/usage/) and
  [Git workflows](https://docs.docker.com/ai/sandboxes/workflows/git/)
- [Network policy](https://docs.docker.com/ai/sandboxes/governance/access-controls/local/)
- [Credentials](https://docs.docker.com/ai/sandboxes/configuration/credentials/)
- [Environment files](https://docs.docker.com/ai/sandboxes/configuration/environment-files/)
- [Settings](https://docs.docker.com/ai/sandboxes/configuration/settings/)
- [Security](https://docs.docker.com/ai/sandboxes/security/)
- [Troubleshooting](https://docs.docker.com/ai/sandboxes/troubleshooting/)
