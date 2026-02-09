# Troubleshooting Guide

Common issues and solutions for Claude Code Sandbox images.

## Build Issues

### "Permission denied" when running build.sh

**Symptom**:
```
bash: ./build.sh: Permission denied
```

**Solution**:
```bash
chmod +x build.sh
./build.sh
```

### "No such file or directory" for Dockerfile

**Symptom**:
```
unable to prepare context: unable to evaluate symlinks in Dockerfile path
```

**Solution**:
Ensure you're in the repository root:
```bash
cd /path/to/claude-sandbox
ls -la Dockerfile.minimal  # Should exist
./build.sh
```

### "Cannot find base image ubuntu:noble"

**Symptom**:
```
Error response from daemon: manifest for ubuntu:noble not found
```

**Solution**:
Pull the base image first:
```bash
docker pull ubuntu:noble
```

If you are behind a corporate proxy or firewall, ensure Docker Hub is accessible. You may also need to authenticate with `docker login`.

### Build hangs during "Fetching..."

**Symptom**:
Build stops responding during package installation

**Possible causes**:
1. Network issues
2. Disk space exhausted
3. Docker daemon issues

**Solutions**:
```bash
# Check disk space
df -h

# Check Docker daemon status
docker info

# Restart Docker daemon
sudo systemctl restart docker  # Linux
# or restart Docker Desktop on Mac/Windows

# Try build with no cache
docker build --no-cache -f Dockerfile.minimal -t claude-sandbox-minimal .
```

### "Package not found" errors

**Symptom**:
```
E: Unable to locate package ripgrep
```

**Solution**:
Update the package lists in Dockerfile:
```dockerfile
RUN apt-get update && apt-get install -y ripgrep
```

The update must be in the same RUN command for Docker caching to work correctly.

## Runtime Issues

### "Permission denied" accessing /workspace

**Symptom**:
```
bash: /workspace/script.sh: Permission denied
```

**Possible causes**:
1. File permissions on host
2. SELinux on Linux hosts

**Solutions**:
```bash
# Fix host file permissions
chmod +x script.sh

# On Linux with SELinux, add :z flag
docker run -it -v $(pwd):/workspace:z claude-sandbox-minimal

# Or disable SELinux for testing (not recommended for production)
sudo setenforce 0
```

### "File not found" in /workspace

**Symptom**:
```
ls: cannot access '/workspace': No such file or directory
```

**Solution**:
Ensure volume is mounted correctly:
```bash
# Use absolute path
docker run -it -v /absolute/path/to/project:/workspace claude-sandbox-minimal

# Or use $(pwd) for current directory
docker run -it -v $(pwd):/workspace claude-sandbox-minimal
```

### "Operation not permitted" for certain commands

**Symptom**:
```
ERROR: Operation denied by permission rules
```

**Solution**:
This is expected behavior. The operation is blocked by security policies. Options:

1. **Check if it's actually needed**: Is there a safer alternative?
2. **Review deny rules**: `cat /etc/claude-code/managed-settings.json`
3. **Create custom image**: If you need the operation, create a custom image with modified rules
4. **Use ask rules**: Some operations require approval (type "yes" when prompted)

### Commands execute but nothing happens

**Symptom**:
Commands appear to run but produce no output or effect

**Possible causes**:
1. Sandbox is blocking the operation silently
2. Network filtering preventing access
3. Hook validation denying the operation

**Diagnostic steps**:
```bash
# Check hook debug log
cat ~/.claude/logs/hook-debug.log

# Check if sandbox is enabled
cat /etc/claude-code/managed-settings.json | jq '.sandbox.enabled'

# Check audit log for the operation
cat ~/.claude/logs/command-log-$(date +%Y-%m-%d).jsonl | tail -20
```

## Configuration Issues

### Custom settings not taking effect

**Symptom**:
Mounted settings.json but behavior unchanged

**Diagnostic**:
```bash
# Verify file is mounted
docker exec <container-id> cat /home/agent/.claude/settings.json

# Check ownership
docker exec <container-id> ls -la /home/agent/.claude/
```

**Solution**:
```bash
# Use :ro flag for read-only mount
docker run -it \
  -v $(pwd)/my-settings.json:/home/agent/.claude/settings.json:ro \
  claude-sandbox-minimal

# Ensure file exists on host before starting container
test -f my-settings.json || echo "File missing!"
```

**Important**: User settings cannot override managed deny/ask rules.

### Hooks not executing

**Symptom**:
Expected hook behavior not occurring

**Diagnostic**:
```bash
# Check if hooks exist
ls -la /home/agent/.claude/hooks/

# Check if hooks are executable
docker exec <container-id> test -x /home/agent/.claude/hooks/pre-command-validator.sh
echo $?  # Should be 0

# Check hook configuration
cat /etc/claude-code/managed-settings.json | jq '.hooks'
```

**Solution**:
```bash
# Make hooks executable
chmod +x settings/hooks/*.sh

# Rebuild image
docker build -f Dockerfile.minimal -t claude-sandbox-minimal .
```

### Environment variables not visible

**Symptom**:
Environment variables passed with -e flag not accessible

**Diagnostic**:
```bash
# Check if variable is set
docker exec <container-id> env | grep MY_VAR
```

**Solution**:
```bash
# Pass explicitly with -e
docker run -it -e MY_VAR=value claude-sandbox-minimal

# Or use --env-file
docker run -it --env-file .env.docker claude-sandbox-minimal
```

## Network Issues

### Cannot access package registries

**Symptom**:
```
Failed to download from https://pypi.org/...
```

**Diagnostic**:
```bash
# Check if domain is in allowedDomains
cat /etc/claude-code/managed-settings.json | jq '.sandbox.allowedDomains'

# Test network access from container
docker exec <container-id> curl -v https://pypi.org
```

**Solution**:
1. Add domain to allowedDomains in custom managed-settings.json
2. Remember: Network filtering is best-effort
3. Use cloud-enabled variant for cloud APIs

### "Network request blocked"

**Symptom**:
```
ERROR: Network request to example.com blocked by sandbox
```

**Expected behavior**: This is working as designed. Network is restricted to allowed domains.

**Solutions**:
1. Add domain to allowedDomains (see CUSTOMIZATION.md)
2. Use git excluded from sandbox: `git clone` should work
3. Download files before mounting them to /workspace

### DNS resolution failures

**Symptom**:
```
Could not resolve host: github.com
```

**Solution**:
```bash
# Use host network mode (reduces isolation)
docker run -it --network host claude-sandbox-minimal

# Or specify DNS servers
docker run -it --dns 8.8.8.8 --dns 8.8.4.4 claude-sandbox-minimal
```

## Performance Issues

### Builds are very slow

**Possible causes**:
1. No layer caching
2. Slow network
3. Insufficient resources

**Solutions**:
```bash
# Increase Docker resources (Docker Desktop)
# Settings → Resources → Increase CPUs and Memory

# Use BuildKit for better caching
export DOCKER_BUILDKIT=1
./build.sh
```

### Container is slow at runtime

**Diagnostic**:
```bash
# Check resource usage
docker stats <container-id>
```

**Solutions**:
```bash
# Increase resource limits
docker run -it \
  --cpus=4 \
  --memory=8g \
  -v $(pwd):/workspace \
  claude-sandbox-minimal

# Check if disk I/O is bottleneck
docker run -it \
  -v $(pwd):/workspace:cached \
  claude-sandbox-minimal  # macOS/Windows only
```

### Large image sizes

**Symptom**:
Images are larger than expected

**Diagnostic**:
```bash
# Check layer sizes
docker history claude-sandbox-minimal

# Find largest layers
docker history claude-sandbox-minimal --no-trunc | sort -k2 -h
```

**Solutions**:
1. Use `--no-cache-dir` for pip/npm
2. Clean apt lists: `rm -rf /var/lib/apt/lists/*`
3. Combine RUN commands to minimize layers
4. Use multi-stage builds for compilation
5. Use .dockerignore to exclude unnecessary files

## Security Issues

### "Cannot override managed settings"

**Symptom**:
User settings trying to override deny rules

**Expected behavior**: This is by design. Managed settings are enforced.

**Solution**:
Create a custom image with modified managed-settings.json (see CUSTOMIZATION.md)

⚠️ **Warning**: Only modify managed settings if you understand the security implications.

### Hooks failing with strange errors

**Symptom**:
```
ERROR: /bin/bash^M: bad interpreter
```

**Cause**: Windows line endings (CRLF) in hook scripts

**Solution**:
```bash
# Convert to Unix line endings
dos2unix settings/hooks/*.sh

# Or with sed
sed -i 's/\r$//' settings/hooks/*.sh

# Rebuild image
docker build -f Dockerfile.minimal -t claude-sandbox-minimal .
```

### Audit logs filling disk

**Symptom**:
`~/.claude/logs/` consuming too much space

**Expected behavior**: Logs rotate after 7 days automatically

**Manual cleanup**:
```bash
# Delete old logs manually
docker exec <container-id> find ~/.claude/logs -name "*.jsonl" -mtime +7 -delete

# Or adjust rotation in post-command-logger.sh
```

## Cloud-Specific Issues

### AWS CLI "Unable to locate credentials"

**Symptom**:
```
Unable to locate credentials. You can configure credentials by running "aws configure".
```

**Solution**:
```bash
# Pass credentials via environment variables
docker run -it \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION \
  -v $(pwd):/workspace \
  claude-sandbox-minimal

# Or mount credentials (less secure)
docker run -it \
  -v ~/.aws:/home/agent/.aws:ro \
  -v $(pwd):/workspace \
  claude-sandbox-minimal
```

### GCP "Application Default Credentials not found"

**Solution**:
```bash
# Mount service account key
docker run -it \
  -v $(pwd):/workspace \
  -v /path/to/key.json:/workspace/.gcp/key.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/workspace/.gcp/key.json \
  claude-sandbox-minimal
```

### Azure CLI "Please run 'az login'"

**Solution**:
```bash
# Use service principal
docker run -it \
  -e AZURE_TENANT_ID \
  -e AZURE_CLIENT_ID \
  -e AZURE_CLIENT_SECRET \
  -v $(pwd):/workspace \
  claude-sandbox-minimal

# Or do az login inside container
docker exec -it <container-id> az login
```

## Debugging Tips

### Enable verbose logging

Add to your user settings:
```json
{
  "debug": true,
  "verbose": true
}
```

### Inspect container state

```bash
# Get container ID
docker ps

# Execute commands in running container
docker exec -it <container-id> bash

# View logs
docker logs <container-id>

# Inspect container config
docker inspect <container-id>
```

### Check hook execution

```bash
# View hook debug log
docker exec <container-id> cat ~/.claude/logs/hook-debug.log

# View audit log
docker exec <container-id> cat ~/.claude/logs/command-log-$(date +%Y-%m-%d).jsonl | jq .

# Test hook manually
echo '{"tool":"Bash","parameters":{"command":"echo test"}}' | \
  docker exec -i <container-id> /home/agent/.claude/hooks/pre-command-validator.sh
echo $?  # 0 = passed, 1 = denied
```

### Compare configurations

```bash
# Compare managed vs user settings
docker exec <container-id> jq -s '.[0] * .[1]' \
  /etc/claude-code/managed-settings.json \
  /home/agent/.claude/settings.json
```

### Test permission rules

Inside container, try operations to see what's allowed:
```bash
# These should be denied
rm -rf /tmp/test  # Destructive operation
curl http://example.com  # Network access

# These should require approval
git commit -m "test"  # State-changing git

# These should be allowed
git status  # Read-only git
pytest  # Test execution
cat file.py  # File reading
```

## Getting Help

### Information to include in bug reports

1. Docker version: `docker version`
2. Host OS: `uname -a` (Linux) or system info (Mac/Windows)
3. Image variant and version
4. Complete error message
5. Steps to reproduce
6. Contents of relevant logs:
   - `~/.claude/logs/hook-debug.log`
   - `~/.claude/logs/command-log-*.jsonl`
   - Docker logs: `docker logs <container-id>`

### Useful commands for diagnostics

```bash
# System info
docker info
docker version
uname -a

# Image info
docker images | grep claude-sandbox
docker history claude-sandbox-minimal

# Container info
docker ps -a
docker inspect <container-id>
docker logs <container-id>
docker stats <container-id>

# Inside container
env  # Environment variables
id  # User info
pwd  # Current directory
ls -la /etc/claude-code/  # Config files
cat /etc/claude-code/managed-settings.json | jq .
```

## Common Error Messages

### "standard_init_linux.go: exec user process caused: no such file or directory"

**Cause**: Script has Windows line endings or wrong shebang

**Solution**: Convert to Unix line endings, check shebang is `#!/bin/bash`

### "OCI runtime create failed: container_linux.go: starting container process caused: exec: \"...\": executable file not found"

**Cause**: Command in CMD or ENTRYPOINT not found

**Solution**: Verify command exists in container: `docker run <image> which <command>`

### "docker: Error response from daemon: Conflict. The container name \"/...\" is already in use"

**Cause**: Container with same name already exists

**Solution**:
```bash
# Remove old container
docker rm <container-name>

# Or use --rm flag for auto-cleanup
docker run --rm -it claude-sandbox-minimal
```

### "pull access denied for claude-sandbox-base"

**Cause**: Trying to pull from registry, but image is local-only

**Solution**: Build locally first:
```bash
./build.sh
```

---

If your issue isn't listed here, check:
- [README.md](../README.md) for general documentation
- [ARCHITECTURE.md](ARCHITECTURE.md) for design details
- [CUSTOMIZATION.md](CUSTOMIZATION.md) for customization guides
- GitHub Issues for similar problems
