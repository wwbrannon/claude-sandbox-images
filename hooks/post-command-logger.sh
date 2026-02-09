#!/bin/bash
# Post-command audit logging hook for Claude Code
# Runs after each tool invocation to log operations and alert on sensitive actions
# Return value is ignored (operation already completed)

set -euo pipefail

# Read JSON input from stdin (includes tool, parameters, and result)
INPUT=$(cat)

# Create logs directory if it doesn't exist
mkdir -p ~/.claude/logs

# Log file with date
LOG_FILE=~/.claude/logs/command-log-$(date +%Y-%m-%d).jsonl

# Extract fields
TOOL=$(echo "$INPUT" | jq -r '.tool')
TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.sessionId // ""')

# Create log entry with full context
LOG_ENTRY=$(echo "$INPUT" | jq -c '{
    timestamp: .timestamp,
    sessionId: .sessionId,
    tool: .tool,
    parameters: .parameters,
    success: (.result.success // true),
    error: (.result.error // null)
}')

# Append to JSONL audit log
echo "$LOG_ENTRY" >> "$LOG_FILE"

# Alert on sensitive operations
if [ "$TOOL" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.parameters.command // ""')

    # Alert on git push
    if echo "$COMMAND" | grep -q '^git push'; then
        echo "[ALERT] Git push operation: $COMMAND" >> ~/.claude/logs/sensitive-ops.log
    fi

    # Alert on package publishing
    if echo "$COMMAND" | grep -qE '^(npm|pip|cargo) publish'; then
        echo "[ALERT] Package publish operation: $COMMAND" >> ~/.claude/logs/sensitive-ops.log
    fi

    # Alert on docker push/login
    if echo "$COMMAND" | grep -qE '^docker (push|login)'; then
        echo "[ALERT] Docker registry operation: $COMMAND" >> ~/.claude/logs/sensitive-ops.log
    fi
fi

# Rotate old logs (keep last 7 days)
find ~/.claude/logs -name "command-log-*.jsonl" -type f -mtime +7 -delete 2>/dev/null || true

# Exit successfully (return value ignored anyway)
exit 0
