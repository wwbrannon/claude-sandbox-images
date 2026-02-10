# Claude Code Sandbox Docker Images

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub issues](https://img.shields.io/github/issues/wwbrannon/claude-sandbox-images)](https://github.com/wwbrannon/claude-sandbox-images/issues)

Lightweight, secure Docker images for running Claude Code in sandboxed environments with defense-in-depth security architecture.

## Overview

This repository provides Docker images for Claude Code with comprehensive security controls:

- **Minimal image** built on Ubuntu 24.04 LTS with Python 3, data science packages, cloud CLIs, cloud SDKs, dev tools, and Claude Code
- **R image** extending minimal with the full R ecosystem (tidyverse, data.table, devtools, and more)
- **Layered security** using container isolation + OS sandboxing + permission rules + validation hooks
- **Audit logging** for compliance and security review

## Available Images

| Image | Base | Description |
|-------|------|-------------|
| `claude-sandbox-minimal` | `ubuntu:noble` (24.04 LTS) | Python 3 + data science packages (pandas, numpy, etc.), cloud CLIs (AWS CLI v2, gcloud, az), cloud Python SDKs (boto3, azure-*, google-cloud-*), dev tools (git, gh, ripgrep, fzf, shellcheck, shfmt, git-delta), Claude Code |
| `claude-sandbox-r` | `claude-sandbox-minimal` | Everything in minimal + R ecosystem (r-base, r-base-dev, r-recommended, littler, tidyverse, data.table, devtools, rmarkdown, and more) |

## Quick Start

These images are designed to run under [`docker sandbox`](https://docs.docker.com/ai/sandboxes/),
which provides microVM isolation with its own Docker daemon. The bubblewrap (bwrap)
OS-level sandbox requires namespace creation, and `docker sandbox` is the supported
way to provide it. Running Claude Code inside a plain `docker run` container will
fail with `bwrap: Creating new namespace failed: Operation not permitted`.

### Basic Usage

```bash
# Run with docker sandbox (recommended)
docker sandbox start my-sandbox --image claude-sandbox-minimal

# Pass arguments to Claude Code after --
docker sandbox start my-sandbox --image claude-sandbox-minimal -- --dangerously-skip-permissions

# Run with R support
docker sandbox start my-sandbox --image claude-sandbox-r
```

### Development / Debugging (plain Docker)

For quick development tasks that don't involve Claude Code (e.g., verifying
installed packages), you can use plain `docker run`:

```bash
docker run -it -v $(pwd):/workspace claude-sandbox-minimal /bin/bash
```

### With Cloud Credentials

All cloud CLIs and SDKs are included in `claude-sandbox-minimal` (and `claude-sandbox-r`).

```bash
# AWS (pass credentials via env, not files)
docker run -it -v $(pwd):/workspace \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION \
  claude-sandbox-minimal

# GCP (mount service account key, use allowlist path)
docker run -it -v $(pwd):/workspace \
  -v /path/to/service-account.json:/workspace/.gcp/key.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/workspace/.gcp/key.json \
  claude-sandbox-minimal

# Azure (use Azure CLI login or env vars)
docker run -it -v $(pwd):/workspace \
  -e AZURE_TENANT_ID \
  -e AZURE_CLIENT_ID \
  -e AZURE_CLIENT_SECRET \
  claude-sandbox-minimal
```

## Building Images

```bash
# Build all images (minimal first, then r)
make build

# Build a single variant (r will build minimal first as a dependency)
make build IMAGE=minimal
make build IMAGE=r

# Build with a specific version tag
make build VERSION=v2.0

# Build and push to a registry
make push REGISTRY=ghcr.io/youruser VERSION=v2.0
```

### Other Targets

```bash
make lint      # ShellCheck, hadolint, JSON validation
make test      # Smoke tests against built images
make scan      # Trivy CVE scan
make list      # Show built images
make clean     # Remove built images
make shell             # Drop into a minimal container
make shell IMAGE=r     # Drop into an R container
```

## Security Model

This sandbox implements **defense-in-depth** with four security layers:

### Layer 1: Container Isolation (Outermost)
**Protects**: Host system from container

- Container filesystem is separate from host
- Host credentials (~/.ssh, ~/.aws on host) are NOT accessible inside container
- Only explicitly mounted volumes are visible
- Container user 'agent' has no relation to host user

**Key principle**: Don't mount sensitive host directories.

### Layer 2: OS-Level Sandbox (bubblewrap)
**Protects**: Container system from Claude's bash commands

- Creates isolated namespace for bash command execution
- Restricts filesystem access (read-only bindings, denied paths)
- Restricts network access (allowedDomains filter)
- Commands run in sandbox jail, cannot escape to container filesystem

**Configuration**: `sandbox.enabled: true` in managed-settings.json

### Layer 3: Permission Rules (Claude Code)
**Protects**: Prevents unwanted operations even if sandbox allows them

- **Deny rules** block dangerous operations (destructive ops, secrets, privilege escalation)
- All other local operations are auto-allowed via `autoAllowBashIfSandboxed`
- Remote operations (push, publish) are controlled by credential availability, not permission rules

**Why needed**: Defense in depth -- deny rules catch dangerous local operations even if the sandbox has a gap

### Layer 4: Validation Hooks (Dynamic Checks)
**Protects**: Context-specific threats that permission rules can't express

- Runs before each tool invocation (after permission check passes)
- Complex validation: parse commands, check symlinks, inspect file sizes
- Dynamic logic that static rules can't express

### What's Blocked

**Completely denied**: destructive filesystem ops (`rm -rf`, `chmod 777`, `chown`), privilege escalation (`sudo`, `su`), network exfiltration (`curl`, `wget`, `nc` except to allowed domains), project secrets (`.env`, `secrets/`, `credentials/`), system file editing (`/etc/`, `/bin/`, shell configs), package managers (`apt-get install`, `brew install`).

**Requires approval**: git push/commit, package publishing, Docker operations, config file editing.

**Automatically allowed**: reading source files, git read-only ops, tests/builds, dev tools.

### Network Access

Network access is restricted to these domains:

- **Package registries**: npmjs.org, pypi.org, crates.io, rubygems.org, maven.org
- **Version control**: github.com, api.github.com, raw.githubusercontent.com
- **Cloud providers**: *.amazonaws.com, *.googleapis.com, *.azure.com
- **Documentation**: stackoverflow.com, stackexchange.com

Network filtering is best-effort via bubblewrap. Don't rely on it as primary security.

### Threat Model

Designed for AI-assisted development where prompt injection is a concern, shared environments needing project isolation, and compliance requirements needing audit trails. NOT designed for untrusted code execution, multi-tenancy at scale, or cryptographic security boundaries.

## Customization

### Extending an Image

The most common customization is extending an existing image with additional tools:

```dockerfile
FROM claude-sandbox-minimal:latest

USER root

# Install additional system packages
RUN apt-get update && apt-get install -y \
    postgresql-client \
    redis-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install additional Python packages
RUN pip3 install --no-cache-dir django celery redis

USER agent
WORKDIR /workspace
```

Build and use:
```bash
docker build -t my-custom-sandbox .
docker run -it -v $(pwd):/workspace my-custom-sandbox
```

### Modifying Permission Rules

You can add allow rules by mounting a custom settings file:

```bash
docker run -it \
  -v $(pwd):/workspace \
  -v $(pwd)/my-settings.json:/home/agent/.claude/settings.json:ro \
  claude-sandbox-minimal
```

You CANNOT override deny rules from managed-settings.json. To change deny rules, create a custom image with a modified `/etc/claude-code/managed-settings.json`.

### Custom Hooks

Hooks are bash scripts that receive JSON via stdin and exit 0 (allow) or 1 (deny). To replace the pre-command hook:

```dockerfile
FROM claude-sandbox-minimal:latest

USER root
COPY my-hook.sh /opt/claude-hooks/pre-command-validator.sh
RUN chmod 755 /opt/claude-hooks/pre-command-validator.sh && \
    chown root:root /opt/claude-hooks/pre-command-validator.sh
USER agent
```

### Adding Network Domains

Create a custom image with a modified `managed-settings.json` that extends the `allowedDomains` list in the `sandbox` section.

## Configuration Files

All config files live under `settings/` in the repo and are copied into images at build time:

| File | In-container path | Owner | Purpose |
|------|-------------------|-------|---------|
| `managed-settings.json` | `/etc/claude-code/managed-settings.json` | root | Enforced security policies (cannot be overridden) |
| `settings.json` | `~/.claude/settings.json` | agent | User settings template (customizable) |
| `hooks/pre-command-validator.sh` | `/opt/claude-hooks/pre-command-validator.sh` | root | Pre-execution validation |
| `hooks/post-command-logger.sh` | `/opt/claude-hooks/post-command-logger.sh` | root | Audit logging (JSONL to `/var/log/claude-audit/`) |
| `SANDBOX-CLAUDE.md` | `/home/agent/CLAUDE.md` | agent | Claude Code context file |

## Troubleshooting

### bwrap: Creating new namespace failed

Every bash command fails with `Operation not permitted`. This happens when running under plain `docker run` -- use `docker sandbox` instead, which provides the namespace support bwrap needs. For development tasks that don't need Claude Code, use `make shell` or run binaries directly.

### Permission denied accessing /workspace

Check host file permissions (`chmod +x script.sh`). On Linux with SELinux, add the `:z` flag to the volume mount.

### Hooks failing with "bad interpreter"

Windows line endings (CRLF) in hook scripts. Fix with `dos2unix settings/hooks/*.sh` and rebuild.

### Can't override deny rules

By design. Managed settings are enforced via `allowManagedPermissionRulesOnly: true`. Create a custom image with a modified managed-settings.json if you need different rules.

### Audit logs

Logs are written to `/var/log/claude-audit/command-audit.jsonl` inside the container and auto-rotate after 7 days.

## Best Practices

1. **Don't mount sensitive directories**: Keep ~/.ssh, ~/.aws, etc. off the container
2. **Use environment variables for credentials**: Pass via `-e` flag, not mounted files
3. **Create custom images for persistence**: Extend these images for additional tools
4. **Review audit logs regularly**: Check `/var/log/claude-audit/` for unexpected operations

## FAQ

**Q: Can I install packages at runtime?**
A: No, package managers are blocked. Create a custom Dockerfile extending these images.

**Q: How do I pass secrets to the container?**
A: Use environment variables via `-e` flag or docker secrets. Never mount credential files directly.

**Q: What if I need a domain that's not in allowedDomains?**
A: Create a custom image with modified `managed-settings.json`. Remember: domain filtering is best-effort.

**Q: Why not just use permission rules without the OS sandbox?**
A: Defense in depth. If permission rules have a bug, the OS sandbox still provides isolation. The sandbox also enables `autoAllowBashIfSandboxed` for better UX.

## Requirements

- Docker 20.10 or later

## License

MIT License - see LICENSE file for details

## Contributing

Contributions welcome! Please:
1. Test changes with both images (minimal and r)
2. Update documentation for any security changes
3. Follow existing Dockerfile patterns
4. Add tests for new validation hooks
