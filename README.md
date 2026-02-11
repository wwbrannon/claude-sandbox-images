# Docker Sandbox Images for Claude Code

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub issues](https://img.shields.io/github/issues/wwbrannon/claude-sandbox-images)](https://github.com/wwbrannon/claude-sandbox-images/issues)

Lightweight images for running Docker-sandboxed Claude Code, with more secure
isolation than the builtin `bwrap` sandbox. The idea is to make
`--dangerously-skip-permissions` safe.

## Quick Start

These images are designed to run under [`docker sandbox`](https://docs.docker.com/ai/sandboxes/), which provides microVM isolation with its own Docker daemon.

```bash
# Run with docker sandbox
# use the claude-sandbox-r image instead for R support
docker sandbox run --load-local-template -t claude-sandbox-base claude ./

# dev / debug: tasks not using Claude Code (e.g., verifying installed packages)
docker run -it -v $(pwd):/workspace claude-sandbox-base /bin/bash
```

## Available Images

| Image | Base | Description |
|-------|------|-------------|
| `claude-sandbox-base` | `ubuntu:noble` (24.04 LTS) | Python 3 + data science packages (pandas, numpy, etc.), cloud CLIs (AWS CLI v2, gcloud, az), cloud Python SDKs (boto3, azure-*, google-cloud-*), dev tools (git, gh, ripgrep, fzf, shellcheck, shfmt, git-delta), Node.js, uv, Claude Code |
| `claude-sandbox-r` | `claude-sandbox-base` | Everything in base + R ecosystem (r-base, r-base-dev, r-recommended, littler, tidyverse, data.table, devtools, rmarkdown, and more via r2u) |

### With Cloud Credentials

All cloud CLIs and SDKs are included in both images. Since `docker sandbox` doesn't accept `-e` flags, pass credentials via a `.env` file in your project directory (which is mounted as `/workspace`). You'll need automation (e.g., the entrypoint script, a shell profile, Makefile targets that use them) to load these variables inside the container.

```bash
# .env (add to .gitignore!)

# AWS
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=us-east-1

# GCP — place the service account key in your project directory
# and point to it relative to /workspace
GOOGLE_APPLICATION_CREDENTIALS=/workspace/.gcp/service-account.json

# Azure
AZURE_TENANT_ID=...
AZURE_CLIENT_ID=...
AZURE_CLIENT_SECRET=...
```

For GCP, copy your service account key into the project (e.g., `.gcp/service-account.json`) and add that path to `.gitignore` as well.

## Building Images

```bash
# Build all images (base first, then r)
make build

# Build with a specific version tag
make build VERSION=v2.0

# Build and push to a registry
make push REGISTRY=ghcr.io/youruser VERSION=v2.0
```

### Other Targets

```bash
$ make help  # Run `make help` for an overview of targets
Development Commands

  build           Build all containers
  help            Show this help message
  lint            Run shellcheck, hadolint, etc.
  push            Push the containers to the registry given by the REGISTRY env variable
  rm              Delete the built containers
  scan            Scan containers for security vulnerabilities with trivy
  shell           Run a shell in the container given by IMAGE (default base)
```

## Security Model

The sandbox implements **defense-in-depth** with three security layers:

### Layer 1: Container / MicroVM Isolation
**Protects**: Host system from container

- `docker sandbox` runs the container in a microVM with its own Docker daemon
- Host credentials (~/.ssh, ~/.aws) are NOT accessible unless explicitly mounted
- Container user `agent` has no sudo access

**Key principle**: Don't mount sensitive host directories. Remote operations (git push, package publishing) are controlled by whether credentials are present, not by permission rules.

### Layer 2: Permission Rules
**Protects**: Prevents privilege escalation and tampering with security configuration

Deny rules in `managed-settings.json` block:
- **Privilege escalation**: `sudo`, `su`, `gosu`
- **Editing managed settings**: `/etc/claude-code/**`
- **Editing hook scripts**: `/opt/claude-hooks/**`

All other operations are auto-allowed via `autoAllowBashIfSandboxed`. Users cannot override deny rules (`allowManagedPermissionRulesOnly: true`).

### Layer 3: Validation Hooks
**Protects**: Against command injection, exfiltration, and resource abuse

The pre-command hook (`hooks/pre-command-validator.sh`) runs before each tool invocation and blocks:
- Command injection patterns (`eval`, backtick injection, pipe to sh)
- Environment variable exfiltration (`env | curl`, `printenv curl`)
- Encoded command execution (`base64 | exec`)
- Symlink attacks (Edit targets outside `/workspace` or `/home/agent`)
- Oversized file reads (>100MB, DoS prevention)

The post-command hook (`hooks/post-command-logger.sh`) logs all operations to `/var/log/claude-audit/command-audit.jsonl` and flags sensitive ops (git push, package publishing) to a separate log.

## Configuration Files

Config files live under `settings/` in the repo; hooks live under `hooks/`. Both are copied into images at build time.

| File | In-container path | Owner | Purpose |
|------|-------------------|-------|---------|
| `settings/managed-settings.json` | `/etc/claude-code/managed-settings.json` | root (444) | Enforced security policies |
| `settings/settings.json` | `~/.claude/settings.json` | agent | User settings template |
| `settings/SANDBOX-CLAUDE.md` | `/home/agent/CLAUDE.md` | agent | Claude Code context file |
| `settings/gitconfig` | `/etc/gitconfig` | root (644) | System-wide git configuration |
| `settings/logrotate-claude` | `/etc/logrotate.d/claude` | root (644) | Audit log rotation config |
| `settings/sandbox-persistent-source.sh` | `/etc/profile.d/sandbox-persistent.sh` | root (644) | Sources sandbox env file in shells |
| `hooks/pre-command-validator.sh` | `/opt/claude-hooks/pre-command-validator.sh` | root (755) | Pre-execution validation |
| `hooks/post-command-logger.sh` | `/opt/claude-hooks/post-command-logger.sh` | root (755) | Audit logging |
| `entrypoint.sh` | `/usr/local/bin/entrypoint.sh` | root (755) | Starts cron, creates logs, drops to agent |

## Customization

### Extending an Image

```dockerfile
FROM claude-sandbox-base:latest

USER root
RUN apt-get update && apt-get install -y \
    postgresql-client redis-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir django celery redis
USER agent
WORKDIR /workspace
```

### Modifying Permission Rules

Since `docker sandbox` only mounts the project directory, customize settings by extending the image. User settings cannot override deny rules.

```dockerfile
FROM claude-sandbox-base:latest
COPY --chown=agent:agent my-settings.json /home/agent/.claude/settings.json
```

To change deny rules, create a custom image with a modified `/etc/claude-code/managed-settings.json`.

### Custom Hooks

Hooks are bash scripts that receive JSON via stdin and exit 0 (allow) or 1 (deny):

```dockerfile
FROM claude-sandbox-base:latest
USER root
COPY my-hook.sh /opt/claude-hooks/pre-command-validator.sh
RUN chmod 755 /opt/claude-hooks/pre-command-validator.sh && \
    chown root:root /opt/claude-hooks/pre-command-validator.sh
USER agent
```

## Troubleshooting

**Hooks failing with "bad interpreter"**: Windows line endings (CRLF). Fix with `dos2unix hooks/*.sh` and rebuild.

**Can't override deny rules**: By design. Create a custom image with modified managed-settings.json.

**Audit logs**: Written to `/var/log/claude-audit/command-audit.jsonl`, auto-rotated via logrotate.

## Best Practices

1. **Don't mount sensitive directories**: Keep ~/.ssh, ~/.aws, etc. off the container
2. **Create custom images for persistence**: Extend these images for additional tools
3. **Review audit logs** when security is important: Check `/var/log/claude-audit/` for unexpected operations

## Contributing

Contributions welcome! Please:
1. Test changes with both images (base and r)
2. Update documentation for any security changes
3. Follow existing Dockerfile patterns
4. Add tests for new validation hooks
