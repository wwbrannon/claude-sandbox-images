#!/bin/bash
# Entrypoint script for Claude Code Sandbox
# Starts cron for log rotation and then runs the main command

set -e

# Start cron daemon as root (must run before switching users)
if [ "$(id -u)" = "0" ]; then
    # Running as root - start cron
    service cron start >/dev/null 2>&1 || true

    # Switch to agent user and run command
    exec gosu agent "${@:-/bin/bash}"
else
    # Already running as non-root, just exec the command
    exec "${@:-/bin/bash}"
fi
