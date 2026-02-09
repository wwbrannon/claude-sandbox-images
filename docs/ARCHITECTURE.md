# Architecture and Design Decisions

This document explains the architectural choices and design rationale for the Claude Code Sandbox images.

## Multi-Tier Architecture

### Design Choice: Base + Specialized Children

We chose a multi-tier architecture with a base image and specialized child images:

```
docker/sandbox-templates:claude-code (upstream)
  └── claude-sandbox-minimal (our base)
      ├── claude-sandbox-python
      ├── claude-sandbox-r
      ├── claude-sandbox-python-cloud
      ├── claude-sandbox-r-cloud
      └── claude-sandbox-full
```

**Rationale**:
- **Avoid duplication**: Security configuration, hooks, and base tools defined once
- **Flexibility**: Teams choose the variant that matches their needs
- **Optimization**: Each variant is optimized for its use case (no bloat)
- **Maintainability**: Updates to security policies propagate to all variants
- **Docker best practices**: Follows standard multi-stage build patterns

**Alternative considered**: Single "kitchen sink" image
- ❌ Would be 5+ GB
- ❌ Most users wouldn't need all tools
- ❌ Slower build times
- ❌ More attack surface

## Security Architecture

### Four Layers of Defense

We implement defense-in-depth with four security layers:

#### Layer 1: Container Isolation
**Purpose**: Protect host from container

**Implementation**:
- Standard Docker isolation
- No privileged mode
- No host path mounts (except /workspace)
- Separate user namespace

**Threats mitigated**:
- Container escape attempts
- Host filesystem access
- Host credential theft

**Key decision**: We trust Docker's isolation for host protection. This is a well-tested boundary with a strong security track record.

#### Layer 2: OS-Level Sandbox (bubblewrap)
**Purpose**: Restrict bash commands within container

**Implementation**:
- Bubblewrap sandboxing enabled for all bash commands
- Network filtering via allowedDomains
- Filesystem access restrictions
- Git and Docker excluded for compatibility

**Configuration**:
```json
{
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": ["git", "docker"]
  }
}
```

**Threats mitigated**:
- Network exfiltration to arbitrary domains
- Filesystem access outside /workspace
- Resource exhaustion

**Key decision**: We use bubblewrap (not alternatives like nsjail) because:
- ✅ Lightweight and fast
- ✅ Well-integrated with Claude Code
- ✅ Sufficient for development workflows
- ✅ Doesn't require privileged containers

**Limitation acknowledged**: Network filtering is best-effort. An attacker could bypass domain filtering. That's why we have Layer 3.

#### Layer 3: Permission Rules
**Purpose**: Declarative policy enforcement

**Implementation**:
- Deny rules block dangerous operations
- Ask rules require user approval for state-changing ops
- Allow rules reduce prompt fatigue
- Enforced by Claude Code before tool execution

**Threats mitigated**:
- Reading project secrets (.env files)
- Destructive filesystem operations
- Unauthorized git pushes
- Package publishing accidents

**Key decision**: Focus deny rules on *realistic container threats*. We don't deny access to ~/.ssh or ~/.aws inside the container because:
1. Container isolation prevents access to host paths anyway
2. Inside the container, these are just empty directories
3. Real threat is .env files in /workspace, which we DO deny

**Why this layer if sandbox exists**:
- Defense in depth (sandbox could have bugs)
- Better UX (clear error messages vs cryptic sandbox failures)
- Covers threats sandbox can't block (e.g., reading .env is filesystem-legal but security-bad)

#### Layer 4: Validation Hooks
**Purpose**: Dynamic, context-aware validation

**Implementation**:
- Pre-command hook runs before each tool invocation
- Receives JSON with tool name and parameters via stdin
- Can perform complex validation logic
- Exit 0 = allow, exit 1 = deny
- Post-command hook logs all operations

**Threats mitigated**:
- Command injection patterns (eval, backticks with curl)
- Environment variable exfiltration
- Symlink attacks (symlink to /etc/passwd)
- DoS via huge file reads
- Complex patterns that can't be expressed in static rules

**Key decision**: Hooks complement rules, not replace them. Rules are fast and declarative. Hooks are slower but can do complex validation:
- Rules: "Block all curl commands"
- Hooks: "Allow curl only with --fail flag to specific domains"

### Why Four Layers?

Each layer protects against different threats:

| Threat | Protected By |
|--------|--------------|
| Access host ~/.ssh | Layer 1 (don't mount it) |
| Read .env in /workspace | Layer 3 (permission deny rules) |
| curl to attacker.com | Layer 2 (sandbox allowedDomains) + Layer 3 (deny curl) |
| Command injection | Layer 3 (deny patterns) + Layer 4 (hook validation) |
| Privilege escalation (sudo/su/gosu) | Layer 3 (deny rules block all privilege escalation) |
| Git push without approval | Layer 3 (ask rules) |
| Symlink to /etc/passwd | Layer 4 (hook validates symlink targets) |

**Design philosophy**: Trust but verify. We trust container isolation for host protection, but add permission rules and hooks for container-internal threats.

## Permission Mode: Default + Auto-Allow

### Design Choice: `default` mode with `autoAllowBashIfSandboxed`

```json
{
  "defaultMode": "default",
  "autoAllowBashIfSandboxed": true
}
```

**Rationale**:
- **Security**: Deny/ask rules still enforced
- **UX**: Reduces prompt fatigue for safe operations
- **Trust model**: We trust the OS sandbox enough to auto-allow sandboxed commands

**Alternative considered**: `strict` mode (always prompt)
- ❌ Prompt fatigue would make sandbox unusable
- ❌ Users would disable it or work around it
- ❌ Doesn't add security (sandbox is already limiting)

**Alternative considered**: `bypass` mode (never prompt)
- ❌ Defeats the purpose of security layers
- ❌ Would allow unauthorized git pushes, package publishing
- ❌ Explicitly disabled: `"disableBypassPermissionsMode": "disable"`

## Hook Implementation

### Design Choice: Bash scripts with JSON input

Hooks are implemented as bash scripts that:
1. Receive JSON via stdin
2. Parse with jq
3. Perform validation
4. Exit 0 (allow) or 1 (deny)

**Rationale**:
- **Simplicity**: Bash is universally available
- **Flexibility**: Can call any command-line tool
- **Performance**: Fast enough for validation checks
- **Maintainability**: Easy to understand and modify

**Alternative considered**: Python hooks
- ❌ Adds Python dependency to base image
- ❌ More complex for simple string checks
- ✅ Could revisit for complex validation logic

### Pre-Command Validator Checks

1. **Command injection patterns**: eval, backticks, pipe to sh
2. **Exfiltration patterns**: env | curl, printenv curl
3. **Encoded execution**: base64 | exec, echo | sh
4. **Symlink validation**: Check Edit targets point to allowed paths
5. **File size checks**: Deny Read of files > 100MB

**Rationale**: These are common attack vectors in AI-assisted coding:
- Prompt injection tries to make Claude run malicious commands
- LLMs can be tricked into exfiltrating environment variables
- Symlinks can be used to escape path restrictions

### Post-Command Logger

Logs every tool invocation to JSONL:
```jsonl
{"timestamp":"2026-02-09T10:30:00Z","tool":"Bash","parameters":{"command":"git status"},"success":true}
```

**Rationale**:
- **Compliance**: Audit trail for security review
- **Forensics**: Investigate incidents after the fact
- **Alerting**: Flag sensitive operations (git push, npm publish)
- **Rotation**: Auto-delete logs older than 7 days

## Network Isolation

### Design Choice: Allowlist of Domains

```json
{
  "allowedDomains": [
    "github.com",
    "npmjs.org",
    "pypi.org",
    "*.pythonhosted.org",
    "crates.io",
    "rubygems.org",
    "cran.r-project.org",
    "*.cran.r-project.org",
    "cloud.r-project.org",
    "cran.rstudio.com",
    "*.rstudio.com",
    "maven.org",
    "*.amazonaws.com",
    "*.googleapis.com",
    "*.azure.com",
    "stackoverflow.com"
  ]
}
```

**Rationale**:
- **Enable development**: Package registries and cloud APIs accessible
- **Block exfiltration**: Arbitrary domains blocked (best-effort)
- **Comprehensive coverage**: Includes CRAN mirrors, PyPI CDN, and major package ecosystems

**Explicitly acknowledged limitation**: This is best-effort. An attacker could:
- Use IP addresses instead of domains
- Tunnel through allowed domains
- Use DNS tunneling

**Why include it anyway?**
- ✅ Defense in depth
- ✅ Stops unsophisticated attempts
- ✅ Low overhead
- ✅ Clear intent (allowlist documents expected access)

## Cloud CLI Variants

### Design Choice: Multi-Cloud Images

We provide cloud-enabled images that include all major cloud CLIs:
- `claude-sandbox-python-cloud` (Python + AWS + GCP + Azure)
- `claude-sandbox-r-cloud` (R + AWS + GCP + Azure)
- `claude-sandbox-full` (Python + R + all clouds)

**Rationale**:
- **Completeness**: Support multi-cloud workflows
- **Simplicity**: One image per language + clouds
- **Flexibility**: All tools available when needed
- **Reasonable size**: ~1GB additional for all cloud CLIs

**Alternative considered**: Separate images per cloud provider
- ❌ More images to maintain
- ❌ Users often work with multiple clouds
- ✅ Could revisit if size becomes problematic

## Build Strategy

### Design Choice: Base First, Then Parallel

```bash
./build.sh
```

1. Build base image (serial)
2. Build all variants (parallel with GNU parallel)
3. Tag with version and latest
4. Optional: push to registry

**Rationale**:
- **Efficiency**: Parallel builds reduce total time
- **Correctness**: Base must complete before variants
- **Flexibility**: Works with or without GNU parallel

### Dockerfile Optimization

**Single RUN command for apt-get**:
```dockerfile
RUN apt-get update && apt-get install -y \
    package1 package2 package3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

**Rationale**:
- Minimizes layers (faster builds)
- Reduces image size (no apt cache)
- Docker best practice

**--no-cache-dir for pip**:
```dockerfile
RUN pip3 install --no-cache-dir package1 package2
```

**Rationale**:
- Reduces image size by ~50MB
- Cache not needed in container (packages are frozen)

## File Placement

### Design Choice: Managed vs User Settings

- **Managed settings**: `/etc/claude-code/managed-settings.json` (root-owned, immutable)
  - Source: `settings/managed-settings.json` in repository
- **User settings**: `~/.claude/settings.json` (agent-owned, mutable)
  - Source: `settings/settings.json` in repository
- **Hooks**: `/home/agent/.claude/hooks/` (agent-owned, managed)
  - Source: `settings/hooks/` in repository

**Rationale**:
- **Separation of concerns**: Security policies vs user preferences
- **Least privilege**: Users can't override security policies
- **Standard practice**: /etc for system-wide, ~ for user-specific
- **Repository organization**: Settings grouped in settings/ directory

**Configuration in managed settings**:
- `allowManagedPermissionRulesOnly: true` - users can't override deny/ask rules
- `allowManagedHooksOnly: true` - users can't disable hooks

## Image Naming

### Design Choice: `claude-sandbox-<variant>`

Examples:
- `claude-sandbox-minimal`
- `claude-sandbox-python`
- `claude-sandbox-python-cloud`
- `claude-sandbox-r-cloud`
- `claude-sandbox-full`

**Rationale**:
- **Clarity**: Obvious what each image contains
- **Consistency**: All images in same namespace
- **Flexibility**: Easy to add new variants
- **Docker conventions**: Hyphenated names, descriptive suffixes

## Key Takeaways

1. **Multi-tier architecture** avoids duplication while maximizing flexibility
2. **Four security layers** provide defense-in-depth against different threats
3. **Permission mode balances security and UX** via auto-allow for sandboxed commands
4. **Hooks complement rules** for dynamic validation that static rules can't express
5. **Network filtering is best-effort** but included for defense-in-depth
6. **Cloud variants optimize for common use cases** without bloat
7. **Build strategy uses parallelism** for efficiency while ensuring correctness

## Future Enhancements

Potential improvements for future versions:

1. **Additional language variants**: Node.js, Go, Rust
2. **More sophisticated hooks**: Python hooks for complex validation
3. **Metrics and monitoring**: Export metrics to observability platforms
4. **Custom sandbox profiles**: Per-project sandbox configurations
5. **Secret detection**: Scan for accidentally committed secrets
6. **Network proxy support**: Route sandbox traffic through proxy
7. **GPU support**: Variants with CUDA for ML workloads
