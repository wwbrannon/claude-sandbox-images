# Claude Code Sandbox Docker Images

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub issues](https://img.shields.io/github/issues/wwbrannon/claude-sandbox-images)](https://github.com/wwbrannon/claude-sandbox-images/issues)

Lightweight, secure Docker images for running Claude Code in sandboxed environments with defense-in-depth security.

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

All cloud CLIs and SDKs are included in both images.

```bash
# AWS (pass credentials via env, not files)
docker run -it -v $(pwd):/workspace \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION \
  claude-sandbox-base

# GCP (mount service account key)
docker run -it -v $(pwd):/workspace \
  -v /path/to/service-account.json:/workspace/.gcp/key.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/workspace/.gcp/key.json \
  claude-sandbox-base

# Azure
docker run -it -v $(pwd):/workspace \
  -e AZURE_TENANT_ID \
  -e AZURE_CLIENT_ID \
  -e AZURE_CLIENT_SECRET \
  claude-sandbox-base
```

## Building Images

```bash
# Build all images (base first, then r)
make build

# Build a single variant (r will build base first as a dependency)
make build IMAGE=base
make build IMAGE=r

# Build with a specific version tag
make build VERSION=v2.0

# Build and push to a registry
make push REGISTRY=ghcr.io/youruser VERSION=v2.0
```

### Other Targets

```bash
make lint              # ShellCheck, hadolint, JSON validation
make test              # Smoke tests against built images
make scan              # Trivy CVE scan
make list              # Show built images
make clean             # Remove built images
make shell             # Drop into a base container
make shell IMAGE=r     # Drop into an R container
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
| `hooks/pre-command-validator.sh` | `/opt/claude-hooks/pre-command-validator.sh` | root (755) | Pre-execution validation |
| `hooks/post-command-logger.sh` | `/opt/claude-hooks/post-command-logger.sh` | root (755) | Audit logging |
| `settings/SANDBOX-CLAUDE.md` | `/home/agent/CLAUDE.md` | agent | Claude Code context file |

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

Mount a custom user settings file (cannot override deny rules):

```bash
docker run -it \
  -v $(pwd):/workspace \
  -v $(pwd)/my-settings.json:/home/agent/.claude/settings.json:ro \
  claude-sandbox-base
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
2. **Use environment variables for credentials**: Pass via `-e` flag, not mounted files
3. **Create custom images for persistence**: Extend these images for additional tools
4. **Review audit logs** when security is important: Check `/var/log/claude-audit/` for unexpected operations

## Contributing

Contributions welcome! Please:
1. Test changes with both images (base and r)
2. Update documentation for any security changes
3. Follow existing Dockerfile patterns
4. Add tests for new validation hooks
