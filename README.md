# Claude Code Sandbox Docker Images

Lightweight, secure Docker images for running Claude Code in sandboxed environments with defense-in-depth security architecture.

## Overview

This repository provides a multi-tier Docker architecture for Claude Code with comprehensive security controls:

- **Base image** with security settings, Unix build toolchain, and modern development utilities
- **Specialized variants** for different use cases (Python, R, cloud CLIs)
- **Layered security** using container isolation + OS sandboxing + permission rules + validation hooks
- **Audit logging** for compliance and security review

## Available Images

### Base Images

| Image | Size | Description |
|-------|------|-------------|
| `claude-sandbox-base` | ~1.6GB | Foundation with build tools, git, gh, ripgrep, fzf, shellcheck, shfmt, git-delta |
| `claude-sandbox-minimal` | ~1.6GB | Alias for base (for compatibility) |

### Language Runtimes

| Image | Size | Description |
|-------|------|-------------|
| `claude-sandbox-python` | ~2.1GB | Python 3 + pytest, black, pylint, jupyter, pandas, numpy |
| `claude-sandbox-r` | ~2.1GB | R + tidyverse, ggplot2, dplyr, devtools, rmarkdown |

### Cloud-Enabled

| Image | Size | Description |
|-------|------|-------------|
| `claude-sandbox-python-aws` | ~2.6GB | Python + AWS CLI v2 + boto3 |
| `claude-sandbox-python-gcp` | ~2.6GB | Python + Google Cloud SDK |
| `claude-sandbox-python-azure` | ~2.6GB | Python + Azure CLI |
| `claude-sandbox-r-aws` | ~2.6GB | R + AWS CLI v2 |
| `claude-sandbox-full` | ~3.6GB | Python + R + all cloud CLIs |

## Quick Start

### Basic Usage

```bash
# Run with your project mounted at /workspace
docker run -it -v $(pwd):/workspace claude-sandbox-python

# Run with specific version
docker run -it -v $(pwd):/workspace claude-sandbox-python:v1.0

# Pass environment variables (for non-sensitive config)
docker run -it -v $(pwd):/workspace -e NODE_ENV=development claude-sandbox-python
```

### With Cloud Credentials

```bash
# AWS (pass credentials via env, not files)
docker run -it -v $(pwd):/workspace \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION \
  claude-sandbox-python-aws

# GCP (mount service account key, use allowlist path)
docker run -it -v $(pwd):/workspace \
  -v /path/to/service-account.json:/workspace/.gcp/key.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/workspace/.gcp/key.json \
  claude-sandbox-python-gcp

# Azure (use Azure CLI login or env vars)
docker run -it -v $(pwd):/workspace \
  -e AZURE_TENANT_ID \
  -e AZURE_CLIENT_ID \
  -e AZURE_CLIENT_SECRET \
  claude-sandbox-python-azure
```

## Building Images

### Build All Variants

```bash
# Build with version tag
./build.sh v1.0

# Build latest
./build.sh

# Build and push to registry
REGISTRY=myregistry.io ./build.sh v1.0
```

### Build Single Variant

```bash
# Build base image first
docker build -f Dockerfile.base -t claude-sandbox-base:v1.0 .

# Build specific variant
docker build -f Dockerfile.python -t claude-sandbox-python:v1.0 .
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

- **Deny rules** block operations before they reach the sandbox
- **Ask rules** require user approval (git push, npm publish)
- **Allow rules** auto-approve safe operations

**Why needed**: Defense in depth, better UX, covers threats sandbox can't block

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
- **`SANDBOX-README.md`**: User guide (included in all images at `/home/agent/README.md`)

## Best Practices

1. **Don't mount sensitive directories**: Keep ~/.ssh, ~/.aws, etc. off the container
2. **Use environment variables for credentials**: Pass via `-e` flag, not mounted files
3. **Create custom images for persistence**: Extend these images for additional tools
4. **Review audit logs regularly**: Check `~/.claude/logs/` for unexpected operations
5. **Understand the security layers**: Each protects against different threats
6. **Use the right variant**: Choose the minimal image that meets your needs

## Requirements

- Docker 20.10 or later
- For building: GNU parallel (optional, speeds up builds)

## License

MIT License - see LICENSE file for details

## Contributing

Contributions welcome! Please:
1. Test changes with all image variants
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
A: Defense in depth. If permission rules have a bug, the OS sandbox still provides isolation. Plus, the sandbox enables `autoAllowBashIfSandboxed` for better UX.

**Q: Can I disable the sandbox to run certain commands?**
A: No, `allowUnsandboxedCommands: false` is enforced. Git and Docker are excluded from sandboxing for compatibility, but the sandbox boundary cannot be bypassed.

**Q: How do I pass secrets to the container?**
A: Use environment variables via `-e` flag or docker secrets. Never mount credential files directly.

**Q: Can I install packages at runtime?**
A: Package managers are blocked. Create a custom Dockerfile extending these images for persistent installations.

**Q: What if I need a domain that's not in allowedDomains?**
A: Create a custom image with modified `managed-settings.json`. Remember: domain filtering is best-effort.

**Q: How do I view the audit logs?**
A: Inside the container: `cat ~/.claude/logs/command-log-$(date +%Y-%m-%d).jsonl`

## Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Security**: See SECURITY.md for responsible disclosure

---

**Remember**: Security is about layers. No single mechanism is perfect, but together they provide robust protection for AI-assisted development workflows.
