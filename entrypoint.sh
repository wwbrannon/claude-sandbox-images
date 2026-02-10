#!/bin/bash
# Entrypoint script for Claude Code Sandbox
# Starts cron for log rotation, pre-creates audit logs, and then runs the main command

set -e

# Must run as root to start cron
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: Entrypoint must run as root to start cron." >&2
    echo "Remove USER directives before ENTRYPOINT in Dockerfile." >&2
    exit 1
fi

# Start cron daemon
service cron start >/dev/null 2>&1 || true

# Pre-create audit log files as root:agent 0660 so the agent can append but not
# delete (directory has sticky bit). Best-effort chattr +a makes them append-only
# when CAP_LINUX_IMMUTABLE is available.
LOG_DIR=/var/log/claude-audit
for logfile in command-audit.jsonl sensitive-ops.log hook-debug.log; do
    touch "$LOG_DIR/$logfile"
    chown root:agent "$LOG_DIR/$logfile"
    chmod 0660 "$LOG_DIR/$logfile"
    chattr +a "$LOG_DIR/$logfile" 2>/dev/null || true
done

# Switch to agent user and run command
exec gosu agent "${@:-/bin/bash}"
