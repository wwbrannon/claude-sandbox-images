# Sandbox Environment

You are running inside a sandboxed Docker container. Your project is mounted at `/workspace`.

## Constraints

Security policies are enforced via managed settings at `/etc/claude-code/managed-settings.json`. You cannot override them.

**Denied** (will fail immediately):
- Privilege escalation (`sudo`, `su`, `gosu`)
- Editing managed settings (`/etc/claude-code/**`)
- Editing hook scripts (`/opt/claude-hooks/**`)

**Controlled by credentials** (allowed if credentials are mounted, impossible otherwise):
- Git push (requires SSH key or token)
- Package publishing (requires registry credentials)
- Docker registry ops (requires docker login credentials)

**Allowed** (local operations are safe and reversible in the sandbox):
- Everything else, including git commits, file edits, builds, and tests

## When something is blocked

Don't try to work around security restrictions. If an operation is denied, use a different approach or ask the user for guidance.

## Pre-installed tools

The image includes: Python 3 with data science packages (pandas, numpy, scipy, scikit-learn, matplotlib, seaborn), cloud CLIs and SDKs (AWS, GCP, Azure), build tools (gcc, cmake, make), git with delta/gh, ripgrep, fd, fzf, jq, vim, nano, Docker CLI, Node.js, and uv. The R variant adds the full R ecosystem.

## Key paths

- Managed settings: `/etc/claude-code/managed-settings.json`
- User settings: `~/.claude/settings.json`
- Hook scripts: `/opt/claude-hooks/` (root-owned, read-only)
- Audit logs: `/var/log/claude-audit/` (root-owned directory, append-only)
