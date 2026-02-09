#!/bin/bash
# Pre-command validation hook for Claude Code
# Runs before each tool invocation to perform dynamic security checks
# Exit 0 = allow, Exit 1 = deny with message to stderr

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract tool and parameters using jq
TOOL=$(echo "$INPUT" | jq -r '.tool')
PARAMS=$(echo "$INPUT" | jq -r '.parameters // {}')

# Log to hook debug file for troubleshooting
echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] PRE-HOOK: tool=$TOOL" >> ~/.claude/logs/hook-debug.log

# Validation: Bash command injection patterns
if [ "$TOOL" = "Bash" ]; then
    COMMAND=$(echo "$PARAMS" | jq -r '.command // ""')

    # Check for eval with user input (common injection vector)
    if echo "$COMMAND" | grep -qE 'eval.*\$'; then
        echo "ERROR: Command injection detected - eval with variable expansion" >&2
        exit 1
    fi

    # Check for command substitution with curl (exfiltration vector)
    if echo "$COMMAND" | grep -qE '\$\(curl|\`curl|curl.*\||curl.*>'; then
        echo "ERROR: Potential exfiltration detected - curl with command substitution or piping" >&2
        exit 1
    fi

    # Check for environment variable exfiltration
    if echo "$COMMAND" | grep -qE 'env.*\|.*curl|printenv.*curl|export.*curl'; then
        echo "ERROR: Environment exfiltration attempt detected" >&2
        exit 1
    fi

    # Check for encoded command execution
    if echo "$COMMAND" | grep -qE 'base64.*exec|base64.*eval|echo.*\|.*sh'; then
        echo "ERROR: Encoded command execution detected" >&2
        exit 1
    fi
fi

# Validation: Edit tool symlink check
if [ "$TOOL" = "Edit" ]; then
    FILE_PATH=$(echo "$PARAMS" | jq -r '.file_path // ""')

    # Check if file is a symlink and resolve target
    if [ -L "$FILE_PATH" ]; then
        TARGET=$(readlink -f "$FILE_PATH" 2>/dev/null || echo "")

        # Deny if symlink points outside /workspace or /home/agent
        if [[ "$TARGET" != /workspace/* ]] && [[ "$TARGET" != /home/agent/* ]]; then
            echo "ERROR: Symlink target outside allowed directories: $TARGET" >&2
            exit 1
        fi

        # Deny if symlink points to sensitive paths
        if [[ "$TARGET" == /etc/* ]] || [[ "$TARGET" == /bin/* ]] || [[ "$TARGET" == /usr/bin/* ]]; then
            echo "ERROR: Symlink target points to system directory: $TARGET" >&2
            exit 1
        fi
    fi
fi

# Validation: Read tool file size check (DoS prevention)
if [ "$TOOL" = "Read" ]; then
    FILE_PATH=$(echo "$PARAMS" | jq -r '.file_path // ""')

    if [ -f "$FILE_PATH" ]; then
        # Get file size in bytes
        FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null || echo "0")

        # Deny files larger than 100MB (DoS prevention)
        MAX_SIZE=$((100 * 1024 * 1024))
        if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
            echo "ERROR: File too large for Read operation ($((FILE_SIZE / 1024 / 1024))MB > 100MB)" >&2
            exit 1
        fi
    fi
fi

# All checks passed
exit 0
