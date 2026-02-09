#!/bin/bash
# Entrypoint script for Claude Code Sandbox
# Starts cron for log rotation and then runs the main command

set -e

# Must run as root to start cron
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: Entrypoint must run as root to start cron." >&2
    echo "Remove USER directives before ENTRYPOINT in Dockerfile." >&2
    exit 1
fi

# Start cron daemon
service cron start >/dev/null 2>&1 || true

# Switch to agent user and run command
exec gosu agent "${@:-/bin/bash}"
