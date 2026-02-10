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

**Why needed**: Defense in depth — deny rules catch dangerous local operations even if the sandbox has a gap

### Layer 4: Validation Hooks (Dynamic Checks)
**Protects**: Context-specific threats that permission rules can't express

- Runs before each tool invocation (after permission check passes)
- Complex validation: parse commands, check symlinks, inspect file sizes
- Dynamic logic that static rules can't express

## What's Blocked

### Completely Denied
- **Destructive filesystem**: `rm -rf *`, `chmod 777 *`, `chown *`
- **Privilege escalation**: `sudo *`, `su *`
- **Network exfiltration**: `curl`, `wget`, `nc` (except to allowed domains)
- **Project secrets**: `**/.env`, `**/.env.*`, `**/secrets/**`, `**/credentials/**`
- **System files**: editing `/etc/**`, `/bin/**`, shell configs
- **Package managers**: `apt-get install`, `brew install` (use pre-built images)

### Requires Approval
- **Git state-changing**: `git push`, `git commit`
- **Package publishing**: `npm publish`, `pip publish`
- **Docker operations**: `docker push`, `docker login`
- **Config editing**: `package.json`, `requirements.txt`, `Cargo.toml`

### Automatically Allowed
- **Read operations**: `**/*.py`, `**/*.js`, `**/*.md`
- **Git read-only**: `git status`, `git diff`, `git log`
- **Tests/builds**: `npm test`, `pytest`, `cargo build`
- **Dev tools**: `jq`, `grep`, `tree`, `ls`

## Network Access

Network access is restricted to these domains:

- **Package registries**: npmjs.org, pypi.org, crates.io, rubygems.org, maven.org
- **Version control**: github.com, api.github.com, raw.githubusercontent.com
- **Cloud providers**: *.amazonaws.com, *.googleapis.com, *.azure.com
- **Documentation**: stackoverflow.com, stackexchange.com

⚠️ **Note**: Network filtering is best-effort via bubblewrap. Don't rely on it as primary security.

## Customization

See [CUSTOMIZATION.md](docs/CUSTOMIZATION.md) for detailed instructions on:
- Creating custom images extending these
- Modifying permission rules
- Adding custom hooks
- Installing additional tools

## Troubleshooting

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for solutions to common issues.

## Architecture

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions and technical details.

## Configuration Files

- **`managed-settings.json`**: Enforced security policies (cannot be overridden by users)
- **`settings.json`**: User settings template (customizable by users)
- **`hooks/pre-command-validator.sh`**: Pre-execution validation hook
- **`hooks/post-command-logger.sh`**: Post-execution audit logging hook
- **`SANDBOX-CLAUDE.md`**: Claude Code context file (included in all images at `/home/agent/CLAUDE.md`)

## Best Practices

1. **Don't mount sensitive directories**: Keep ~/.ssh, ~/.aws, etc. off the container
2. **Use environment variables for credentials**: Pass via `-e` flag, not mounted files
3. **Create custom images for persistence**: Extend these images for additional tools
4. **Review audit logs regularly**: Check `/var/log/claude-audit/` for unexpected operations
5. **Understand the security layers**: Each protects against different threats
6. **Use the right variant**: Choose the minimal image that meets your needs

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

## Security Considerations

### What This Protects Against
- ✅ Prompt injection attempts to read project secrets
- ✅ Command injection in bash commands
- ✅ Accidental destructive operations
- ✅ Unauthorized state changes (git push, npm publish)
- ✅ Resource abuse (reading huge files)
- ✅ Host system access (via container isolation)

### What This Doesn't Protect Against
- ❌ Mounting sensitive host directories (user responsibility)
- ❌ Container escape vulnerabilities (keep Docker updated)
- ❌ Side-channel attacks or timing attacks
- ❌ Determined adversaries with physical access

### Threat Model

This sandbox is designed for:
- **AI-assisted development** where prompt injection is a concern
- **Shared environments** where isolation between projects is needed
- **Compliance requirements** needing audit trails
- **Educational settings** where safety guardrails are helpful

This sandbox is NOT designed for:
- **Untrusted code execution** (use dedicated sandboxing solutions)
- **Multi-tenancy** at scale (use proper container orchestration)
- **Cryptographic security** boundaries (layer additional controls)

## FAQ

**Q: Why not just use permission rules without the OS sandbox?**
A: Defense in depth. If permission rules have a bug, the OS sandbox still provides isolation. The sandbox also enables `autoAllowBashIfSandboxed` for better UX — remote operations like `git push` and `npm publish` are controlled at the infrastructure level by whether credentials are mounted into the container, which is a stronger boundary than permission rules.

**Q: Can I disable the sandbox to run certain commands?**
A: No, `allowUnsandboxedCommands: false` is enforced. Git and Docker are excluded from sandboxing for compatibility, but the sandbox boundary cannot be bypassed.

**Q: How do I pass secrets to the container?**
A: Use environment variables via `-e` flag or docker secrets. Never mount credential files directly.

**Q: Can I install packages at runtime?**
A: Package managers are blocked. Create a custom Dockerfile extending these images for persistent installations.

**Q: What if I need a domain that's not in allowedDomains?**
A: Create a custom image with modified `managed-settings.json`. Remember: domain filtering is best-effort.

**Q: How do I view the audit logs?**
A: Inside the container: `cat /var/log/claude-audit/command-audit.jsonl`

## Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Security**: See SECURITY.md for responsible disclosure

---

**Remember**: Security is about layers. No single mechanism is perfect, but together they provide robust protection for AI-assisted development workflows.
