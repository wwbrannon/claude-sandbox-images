# Customization Guide

This guide shows you how to customize the Claude Code Sandbox images for your specific needs.

## Creating Custom Images

### Extending an Existing Variant

The most common customization is extending an existing image with additional tools:

```dockerfile
# custom-image/Dockerfile
FROM claude-sandbox-python:latest

# Switch to root for installations
USER root

# Install additional tools
RUN apt-get update && apt-get install -y \
    postgresql-client \
    redis-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install additional Python packages
RUN pip3 install --no-cache-dir \
    django \
    celery \
    redis \
    psycopg2-binary

# Switch back to agent user
USER agent
WORKDIR /workspace
```

Build and use:
```bash
docker build -t my-custom-sandbox -f custom-image/Dockerfile .
docker run -it -v $(pwd):/workspace my-custom-sandbox
```

### Creating a New Variant

To create a completely new variant (e.g., Node.js):

```dockerfile
# Dockerfile.nodejs
FROM claude-sandbox-minimal

USER root

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install global npm packages
RUN npm install -g \
    typescript \
    ts-node \
    eslint \
    prettier \
    jest

# Set Node environment
ENV NODE_ENV=development \
    NPM_CONFIG_LOGLEVEL=warn

USER agent
WORKDIR /workspace
```

## Modifying Permission Rules

### Adding Project-Specific Allow Rules

You can add allow rules without creating a custom image by mounting a custom settings file:

```json
// my-settings.json
{
  "permissionRules": {
    "allow": [
      {
        "tool": "Bash",
        "pattern": "make deploy-staging",
        "reason": "Deploy to staging environment"
      },
      {
        "tool": "Edit",
        "pattern": "**/config/production.yaml",
        "reason": "Update production config"
      }
    ]
  }
}
```

Mount it:
```bash
docker run -it \
  -v $(pwd):/workspace \
  -v $(pwd)/my-settings.json:/home/agent/.claude/settings.json:ro \
  claude-sandbox-python
```

**Important**: You CANNOT override deny rules from managed-settings.json.

### Modifying Managed Settings (Advanced)

To change deny rules, create a custom image with modified managed settings:

```dockerfile
FROM claude-sandbox-python:latest

USER root

# Copy custom managed settings
COPY custom-managed-settings.json /etc/claude-code/managed-settings.json
RUN chown root:root /etc/claude-code/managed-settings.json

USER agent
```

⚠️ **Security Warning**: Modifying managed settings weakens security. Only do this if you understand the implications.

### Example: Allow curl for Specific Domain

```json
// custom-managed-settings.json
{
  "permissionRules": {
    "deny": [
      // Keep most deny rules, but remove curl block
    ],
    "allow": [
      {
        "tool": "Bash",
        "pattern": "curl https://api.mycompany.com/*",
        "reason": "Access internal API"
      }
    ]
  }
}
```

**Better approach**: Add the domain to sandbox allowedDomains instead of removing the deny rule.

## Custom Validation Hooks

### Creating a Custom Pre-Command Hook

Example: Deny git push to main branch

```bash
#!/bin/bash
# custom-hooks/no-push-to-main.sh

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool')

if [ "$TOOL" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.parameters.command // ""')

    # Block git push to main
    if echo "$COMMAND" | grep -qE '^git push.*main'; then
        echo "ERROR: Direct push to main branch is not allowed. Use feature branches." >&2
        exit 1
    fi
fi

exit 0
```

Use in custom image:
```dockerfile
FROM claude-sandbox-python:latest

USER root

# Copy custom hook
COPY custom-hooks/no-push-to-main.sh /opt/claude-hooks/pre-command-validator.sh
RUN chmod 755 /opt/claude-hooks/pre-command-validator.sh
RUN chown root:root /opt/claude-hooks/pre-command-validator.sh

USER agent
```

### Chaining Hooks

To run multiple hooks, create a wrapper:

```bash
#!/bin/bash
# hooks/multi-hook.sh

INPUT=$(cat)

# Run original validator
echo "$INPUT" | /opt/claude-hooks/original-validator.sh || exit 1

# Run custom validator
echo "$INPUT" | /opt/claude-hooks/custom-validator.sh || exit 1

# All passed
exit 0
```

### Custom Post-Command Hook

Example: Send alerts to Slack

```bash
#!/bin/bash
# custom-hooks/slack-logger.sh

set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool')

# Run original logger
echo "$INPUT" | /opt/claude-hooks/original-logger.sh

# Send sensitive operations to Slack
if [ "$TOOL" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.parameters.command // ""')

    if echo "$COMMAND" | grep -qE '^git push'; then
        # Send to Slack webhook (requires SLACK_WEBHOOK_URL env var)
        if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
            curl -X POST "$SLACK_WEBHOOK_URL" \
                -H 'Content-Type: application/json' \
                -d "{\"text\":\"🚨 Git push detected: $COMMAND\"}"
        fi
    fi
fi

exit 0
```

## Adding Network Domains

### Extend allowedDomains List

```json
// custom-managed-settings.json
{
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": ["git", "docker"],
    "allowedDomains": [
      // Original domains
      "github.com",
      "npmjs.org",
      "pypi.org",
      // Add custom domains
      "api.mycompany.com",
      "*.internalnetwork.local",
      "metrics.monitoring.io"
    ]
  }
}
```

⚠️ **Remember**: Network filtering is best-effort. Don't rely on it for security.

## Installing Additional Tools

### System Packages

```dockerfile
FROM claude-sandbox-minimal

USER root

RUN apt-get update && apt-get install -y \
    imagemagick \
    ffmpeg \
    poppler-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER agent
```

### Language Packages

```dockerfile
FROM claude-sandbox-python

USER root

# Install from requirements file
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt
RUN rm /tmp/requirements.txt

USER agent
```

### Binary Downloads

```dockerfile
FROM claude-sandbox-minimal

USER root

# Install terraform
RUN TERRAFORM_VERSION=1.7.0 && \
    curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    mv terraform /usr/local/bin/ && \
    chmod +x /usr/local/bin/terraform && \
    rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

USER agent
```

## Environment Variables

### Adding Default Environment Variables

```dockerfile
FROM claude-sandbox-python

# Set project-specific defaults
ENV PROJECT_ENV=sandbox \
    DEBUG=true \
    LOG_LEVEL=info
```

### Runtime Environment Variables

Pass at runtime:
```bash
docker run -it \
  -v $(pwd):/workspace \
  -e AWS_PROFILE=dev \
  -e DATABASE_URL=postgres://localhost/mydb \
  -e API_KEY=xyz \
  claude-sandbox-python
```

Or use an env file:
```bash
# .env.docker
AWS_PROFILE=dev
DATABASE_URL=postgres://localhost/mydb
API_KEY=xyz
```

```bash
docker run -it \
  -v $(pwd):/workspace \
  --env-file .env.docker \
  claude-sandbox-python
```

⚠️ **Security**: Never commit .env files with real credentials. Use secrets management.

## User Configuration

### Custom Shell Configuration

```dockerfile
FROM claude-sandbox-python

USER agent

# Add custom bash configuration
RUN echo 'alias ll="ls -lah"' >> ~/.bashrc && \
    echo 'export PS1="\u@\h:\w\$ "' >> ~/.bashrc && \
    echo 'export HISTSIZE=10000' >> ~/.bashrc
```

### Git Configuration

```dockerfile
FROM claude-sandbox-python

USER agent

# Configure git for user
RUN git config --global user.name "Claude Agent" && \
    git config --global user.email "agent@example.com" && \
    git config --global init.defaultBranch main && \
    git config --global pull.rebase true
```

## Volume Mounts

### Multiple Project Directories

```bash
docker run -it \
  -v $(pwd)/frontend:/workspace/frontend:ro \
  -v $(pwd)/backend:/workspace/backend \
  -v $(pwd)/shared:/workspace/shared:ro \
  claude-sandbox-python
```

### Persistent Cache Directories

```bash
# Create named volumes for caches
docker volume create claude-pip-cache
docker volume create claude-npm-cache

docker run -it \
  -v $(pwd):/workspace \
  -v claude-pip-cache:/home/agent/.cache/pip \
  -v claude-npm-cache:/home/agent/.npm \
  claude-sandbox-python
```

### SSH Keys for Git (Advanced)

If you need to clone private repos:

```bash
# Start SSH agent and add key
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa

# Mount SSH agent socket
docker run -it \
  -v $(pwd):/workspace \
  -v $SSH_AUTH_SOCK:/ssh-agent \
  -e SSH_AUTH_SOCK=/ssh-agent \
  claude-sandbox-python
```

⚠️ **Security**: Only mount SSH agent socket, never mount ~/.ssh directory directly.

## Docker Compose

### Multi-Container Setup

```yaml
# docker-compose.yml
version: '3.8'

services:
  claude:
    image: claude-sandbox-python:latest
    volumes:
      - ./project:/workspace
      - pip-cache:/home/agent/.cache/pip
    environment:
      - DATABASE_URL=postgres://postgres:password@db:5432/mydb
      - REDIS_URL=redis://redis:6379
    depends_on:
      - db
      - redis

  db:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=mydb
    volumes:
      - postgres-data:/var/lib/postgresql/data

  redis:
    image: redis:7
    volumes:
      - redis-data:/data

volumes:
  pip-cache:
  postgres-data:
  redis-data:
```

Usage:
```bash
docker-compose run --rm claude
```

## Testing Custom Images

### Verification Script

```bash
#!/bin/bash
# test-custom-image.sh

set -e

IMAGE_NAME="$1"

echo "Testing $IMAGE_NAME..."

# Test 1: Image exists
docker inspect "$IMAGE_NAME" > /dev/null

# Test 2: Can start container
CONTAINER=$(docker run -d "$IMAGE_NAME" sleep 60)

# Test 3: Files exist
docker exec "$CONTAINER" test -f /etc/claude-code/managed-settings.json
docker exec "$CONTAINER" test -f /home/agent/.claude/settings.json
docker exec "$CONTAINER" test -x /opt/claude-hooks/pre-command-validator.sh

# Test 4: Tools are installed
docker exec "$CONTAINER" git --version
docker exec "$CONTAINER" jq --version

# Cleanup
docker stop "$CONTAINER"
docker rm "$CONTAINER"

echo "All tests passed!"
```

## Best Practices

### 1. Use Multi-Stage Builds for Compiling

```dockerfile
# Build stage
FROM claude-sandbox-minimal AS builder

USER root

RUN apt-get update && apt-get install -y build-essential
COPY source/ /build/
WORKDIR /build
RUN make

# Runtime stage
FROM claude-sandbox-minimal

USER root
COPY --from=builder /build/output /usr/local/bin/
USER agent
```

### 2. Minimize Layers

**Bad**:
```dockerfile
RUN apt-get update
RUN apt-get install -y package1
RUN apt-get install -y package2
RUN apt-get clean
```

**Good**:
```dockerfile
RUN apt-get update && \
    apt-get install -y package1 package2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
```

### 3. Use .dockerignore

```
# .dockerignore
.git
.env
*.log
node_modules/
__pycache__/
*.pyc
.pytest_cache/
settings/
```

### 4. Version Pin for Reproducibility

```dockerfile
# Pin exact versions
RUN pip3 install --no-cache-dir \
    django==5.0.1 \
    celery==5.3.6 \
    redis==5.0.1
```

### 5. Document Customizations

Add a README to your custom image:
```dockerfile
COPY CUSTOM-README.md /home/agent/CUSTOMIZATIONS.md
```

**Note**: The settings/ directory in the repository contains the configuration files that are copied into images during build.

## Troubleshooting

### "Permission denied" when building

Make sure hook scripts are executable:
```bash
chmod +x hooks/*.sh
```

### "Package not found" errors

Update package lists first:
```dockerfile
RUN apt-get update && apt-get install -y ...
```

### Large image sizes

- Use `--no-cache-dir` for pip/npm
- Clean apt lists: `rm -rf /var/lib/apt/lists/*`
- Use multi-stage builds for compilation
- Check for duplicate layers

### Custom settings not working

- Verify file is mounted: `docker exec <container> cat /home/agent/.claude/settings.json`
- Check ownership: `docker exec <container> ls -la /home/agent/.claude/`
- Remember: You can't override managed deny rules

## Example: Complete Custom Image

```dockerfile
# Dockerfile.custom-python
FROM claude-sandbox-python:latest

USER root

# Install additional system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    redis-tools \
    imagemagick \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python packages from requirements
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Copy custom configuration
COPY custom-settings.json /home/agent/.claude/custom-settings.json
COPY custom-hooks/ /opt/claude-hooks/
RUN chown -R root:root /opt/claude-hooks && \
    chmod 755 /opt/claude-hooks/*.sh

# Set project environment
ENV PROJECT_NAME=myproject \
    LOG_LEVEL=info

USER agent

# Add bash aliases
RUN echo 'alias pytest-watch="pytest-watch --clear"' >> ~/.bashrc

WORKDIR /workspace
```

Build and run:
```bash
docker build -t my-custom-claude -f Dockerfile.custom-python .
docker run -it -v $(pwd):/workspace my-custom-claude
```

## Further Reading

- [ARCHITECTURE.md](ARCHITECTURE.md) - Design decisions and rationale
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [Docker documentation](https://docs.docker.com/) - Official Docker docs
