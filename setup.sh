#!/usr/bin/env bash
# One-time hardening for Claude Code in Docker Sandboxes.
# Run after `sbx login` and before the first `sbx run`:
#
#   bash setup.sh
#
# Settings and policy rules set here are global: they apply to every sandbox.
set -euo pipefail

# --- Settings ----------------------------------------------------------------

# Sandboxes may not use your host SSH agent. It is on by default when
# SSH_AUTH_SOCK is set, which lets the agent sign git pushes and SSH logins
# with your keys.
sbx settings set ssh.agentForwardingEnabled false

# Sandboxed processes may not open URLs in your host browser. A URL opened there
# reaches any site, outside the network policy. Claude's /login also prints the
# URL, so you can still open it yourself.
sbx settings set browser.enabled false

# No shared skills store between sandboxes (experimental feature).
sbx settings set skills.defaultMode off

# Apply settings that need a daemon restart.
sbx daemon restart

# --- Network policy ----------------------------------------------------------

# Start from Locked Down: no baseline allowlist. Balanced allows many hosts,
# including broad patterns such as *.googleapis.com.
if ! sbx policy init deny-all; then
  echo "Network policy is already initialized; run 'sbx policy reset' to change the preset." >&2
fi

# The Anthropic API. The built-in Claude kit adds its own rules as well; this
# keeps the API reachable regardless.
sbx policy allow network api.anthropic.com

# Claude Code telemetry (Claude Code 2.1.314 sent logs here in the OpenShell
# tests). Deny rules win over allow rules, including rules added by kits.
sbx policy deny network http-intake.logs.us5.datadoghq.com

# Optional rules: uncomment what you need.

# Package registries.
# sbx policy allow network "registry.npmjs.org,pypi.org,files.pythonhosted.org"

# GitHub over HTTPS (git and the API).
# sbx policy allow network "github.com,api.github.com"
# Block creating gists, an easy way to send data out with a GitHub token.
# sbx policy deny network api.github.com --method POST --path '/gists'

sbx policy ls --wide
