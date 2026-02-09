# Claude Code Sandbox Environment

Welcome to your Claude Code sandbox environment! This container provides a secure, isolated workspace for AI-assisted development.

## What's Included

### Base Tools
- **Build toolchain**: gcc, g++, make, cmake, autotools
- **Version control**: git, git-lfs, gh (GitHub CLI)
- **Modern CLI tools**: ripgrep, fd, fzf, tree, bat, git-delta
- **Development utilities**: jq, curl, wget, vim, nano
- **Code quality**: shellcheck, shfmt

### Language-Specific Variants

**Python** (`claude-sandbox-python`):
- Python 3 with pip, pytest, black, pylint, mypy
- Data science: pandas, numpy, matplotlib, seaborn
- Interactive: ipython, jupyter, jupyterlab

**R** (`claude-sandbox-r`):
- R base with tidyverse, ggplot2, dplyr
- Development: devtools, testthat
- Documentation: rmarkdown, knitr

**Cloud-Enabled Variants**:
- `-aws`: AWS CLI v2 + boto3
- `-gcp`: Google Cloud SDK + google-cloud libraries
- `-azure`: Azure CLI + azure-sdk
- `-full`: Python + R + all cloud CLIs

## Security Model

This sandbox uses **layered security** for defense in depth:

### Layer 1: Container Isolation
- Container filesystem is separate from your host
- Only explicitly mounted volumes are accessible
- Host credentials (~/.ssh, ~/.aws) are NOT accessible unless you mount them

### Layer 2: OS-Level Sandbox (bubblewrap)
- Sandboxes bash commands in an isolated namespace
- Restricts network access to allowed domains only
- Prevents access to sensitive paths

### Layer 3: Permission Rules
- **Denied**: Destructive operations (rm -rf, chmod 777), network exfiltration (curl/wget), reading secrets (.env files)
- **Requires approval**: Git push/commit, package publishing, Docker operations
- **Auto-allowed**: Read operations, tests, builds, development tools

### Layer 4: Validation Hooks
- Pre-command validation checks for injection patterns
- Post-command audit logging to `~/.claude/logs/`
- All operations logged for security review

## What's Blocked

### Completely Denied
- Reading project secrets: `.env`, `.env.*`, `secrets/`, `credentials/`
- Destructive filesystem: `rm -rf`, `chmod 777`, `chown`
- Privilege escalation: `sudo`, `su`, `gosu`
- Network exfiltration: `curl`, `wget`, `nc` (except to allowed domains)
- Package installation: `apt-get install`, `brew install`
- System file editing: `/etc/`, `/bin/`, shell configs

### Requires Approval
- Git operations: `git push`, `git commit`
- Package publishing: `npm publish`, `pip publish`
- Docker operations: `docker push`, `docker login`
- Dependency changes: editing `package.json`, `requirements.txt`

### Automatically Allowed
- Reading source code (`.py`, `.js`, `.ts`, `.md`, etc.)
- Git read operations: `git status`, `git diff`, `git log`
- Running tests: `pytest`, `npm test`, `cargo test`
- Running builds: `npm run build`, `cargo build`
- Development tools: `jq`, `grep`, `tree`, `ls`

## Network Access

The sandbox allows network access to these domains only:
- **Package registries**: npmjs.org, pypi.org (including pythonhosted.org), crates.io, rubygems.org, cran.r-project.org (including CRAN mirrors), maven.org
- **Version control**: github.com, api.github.com, raw.githubusercontent.com
- **Cloud providers**: *.amazonaws.com, *.googleapis.com, *.azure.com
- **Documentation**: stackoverflow.com, stackexchange.com

⚠️ **Note**: Network filtering is best-effort and can be bypassed. Don't rely on it as your primary security mechanism.

## Working with the Sandbox

### Accessing Your Project
Your project should be mounted at `/workspace`:
```bash
docker run -it -v /path/to/your/project:/workspace claude-sandbox-python
```

### Installing Additional Packages
If you need packages not included in the image:
1. **Temporary**: Install in container (lost on restart)
2. **Persistent**: Create a custom Dockerfile extending this image
3. **Best practice**: Use project-local package managers (pip install --user, npm install)

### Viewing Settings
- **Managed settings** (enforced): `/etc/claude-code/managed-settings.json`
- **User settings** (customizable): `~/.claude/settings.json`
- **Audit logs**: `~/.claude/logs/command-log-YYYY-MM-DD.jsonl`

### Customizing User Settings
You can customize `~/.claude/settings.json` to:
- Add project-specific allow rules
- Set environment variables (non-sensitive only!)
- Configure editor preferences
- Change output style

⚠️ **You cannot override**: Deny rules, ask rules, sandbox settings, or hook configuration. These are managed and enforced.

## Troubleshooting

### "Operation denied by permission rules"
- Check `/etc/claude-code/managed-settings.json` to see the deny rule
- The operation is blocked for security. Consider if there's a safer alternative.
- If you need the operation, create a custom image with adjusted rules.

### "Network request failed"
- Check if the domain is in the sandbox's allowedDomains list
- Remember: Network filtering is best-effort, not guaranteed
- For development, consider adding the domain to your custom settings

### "Hook validation failed"
- Check `~/.claude/logs/hook-debug.log` for details
- The operation was blocked by dynamic validation
- Common causes: command injection patterns, symlink attacks, oversized files

### "File not found" or "Permission denied"
- Ensure your project is mounted at `/workspace`
- Check that you're not trying to access host paths (only container paths work)
- Remember: Host credentials directories are NOT accessible

## Best Practices

1. **Don't mount sensitive host directories**: Keep ~/.ssh, ~/.aws, etc. off the container
2. **Use secrets management**: Pass credentials via environment variables, not files
3. **Review audit logs**: Check `~/.claude/logs/` regularly for unexpected operations
4. **Create custom images**: For persistent package installations, extend these images
5. **Understand the layers**: Each security layer protects against different threats
6. **Test safely**: The sandbox lets you experiment without risking your host system

## Getting Help

- **View current settings**: `cat /etc/claude-code/managed-settings.json`
- **Check logs**: `cat ~/.claude/logs/command-log-$(date +%Y-%m-%d).jsonl`
- **Debug hooks**: `cat ~/.claude/logs/hook-debug.log`
- **View this guide**: `cat ~/README.md`

## What Makes This Secure?

This isn't just a Docker container with Claude Code installed. It's a **defense-in-depth** architecture:

1. **Container isolation** prevents accessing your host system
2. **OS-level sandboxing** restricts bash commands to safe operations
3. **Permission rules** deny dangerous operations before they execute
4. **Validation hooks** catch complex attack patterns dynamically
5. **Audit logging** provides visibility into all operations

Together, these layers protect against prompt injection, command injection, credential theft, and resource abuse.

---

**Remember**: Security is about **layers**. No single mechanism is perfect, but together they provide robust protection for AI-assisted development workflows.

Happy coding! 🚀
