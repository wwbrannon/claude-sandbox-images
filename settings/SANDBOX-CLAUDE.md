# Sandbox Environment

You are running inside a sandboxed Docker container. Your project is mounted at `/workspace`.

## Constraints

Security policies are enforced via managed settings at `/etc/claude-code/managed-settings.json`. You cannot override them.

**Denied** (will fail immediately):
- Destructive filesystem ops (`rm -rf`, `chmod 777`, `chown`)
- Privilege escalation (`sudo`, `su`)
- Network tools (`curl`, `wget`, `nc`) except to allowed domains
- Package installation (`apt-get install`, `brew install`) -- use what's pre-installed
- Reading secrets (`.env`, `.env.*`, `secrets/`, `credentials/`)
- Editing system files (`/etc/`, `/bin/`, shell configs)

**Controlled by credentials** (allowed if credentials are mounted, impossible otherwise):
- Git push (requires SSH key or token)
- Package publishing (requires registry credentials)
- Docker registry ops (requires docker login credentials)

**Allowed** (local operations are safe and reversible in the sandbox):
- Everything else, including git commits, file edits, builds, and tests

**Network access** is restricted to: package registries (npmjs, pypi, crates.io, CRAN), GitHub, cloud provider APIs (AWS, GCP, Azure), and Stack Overflow/Exchange.

## When something is blocked

Don't try to work around security restrictions. If an operation is denied, use a different approach or ask the user for guidance.

## Pre-installed tools

The image includes: Python 3 with data science packages (pandas, numpy, scipy, scikit-learn, matplotlib, seaborn), cloud CLIs and SDKs (AWS, GCP, Azure), build tools (gcc, cmake, make), git with delta/gh, ripgrep, fd, fzf, jq, vim, nano, Docker CLI, Node.js, and uv. The R variant adds the full R ecosystem.

## Key paths

- Managed settings: `/etc/claude-code/managed-settings.json`
- User settings: `~/.claude/settings.json`
- Audit logs: `~/.claude/logs/`
- Hooks: `~/.claude/hooks/`
