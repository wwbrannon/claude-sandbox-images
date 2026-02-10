#!/bin/bash
# Post-command audit logging hook for Claude Code
# Runs after each tool invocation to log operations and alert on sensitive actions
# Return value is ignored (operation already completed)

set -euo pipefail

# Read JSON input from stdin (includes tool, parameters, and result)
INPUT=$(cat)

# Log paths (pre-created by entrypoint as root:agent 0660)
LOG_FILE=/var/log/claude-audit/command-audit.jsonl
SENSITIVE_LOG=/var/log/claude-audit/sensitive-ops.log

# Extract fields
TOOL=$(echo "$INPUT" | jq -r '.tool')

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
        echo "[ALERT] Git push operation: $COMMAND" >> "$SENSITIVE_LOG"
    fi

    # Alert on package publishing
    if echo "$COMMAND" | grep -qE '^(npm|pip|cargo) publish'; then
        echo "[ALERT] Package publish operation: $COMMAND" >> "$SENSITIVE_LOG"
    fi

    # Alert on docker push/login
    if echo "$COMMAND" | grep -qE '^docker (push|login)'; then
        echo "[ALERT] Docker registry operation: $COMMAND" >> "$SENSITIVE_LOG"
    fi
fi

# Log rotation is handled by logrotate (see /etc/logrotate.d/claude)

# Exit successfully (return value ignored anyway)
exit 0
