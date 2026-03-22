#!/bin/bash
# Install Tenvy hooks for Claude Code
# This script installs the hook handler and updates Claude settings

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

echo "Installing Tenvy hooks..."

# Create hooks directory
mkdir -p "$HOOKS_DIR"

# Copy hook handler
cp "$SCRIPT_DIR/chat-sessions-hook.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR/chat-sessions-hook.sh"
echo "  Installed hook handler to $HOOKS_DIR/chat-sessions-hook.sh"

# Merge hooks into settings
if [ -f "$SETTINGS_FILE" ]; then
    # Backup existing settings
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup"
    echo "  Backed up existing settings to ${SETTINGS_FILE}.backup"

    # Merge hooks using jq
    if command -v jq &> /dev/null; then
        HOOKS_JSON=$(cat "$SCRIPT_DIR/claude-settings-hooks.json")
        EXISTING=$(cat "$SETTINGS_FILE")

        # Deep merge the hooks
        echo "$EXISTING" | jq --argjson hooks "$HOOKS_JSON" '
            .hooks = (.hooks // {}) * $hooks.hooks
        ' > "${SETTINGS_FILE}.tmp"
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        echo "  Merged hooks into existing settings"
    else
        echo "  Warning: jq not found, please manually merge hooks from:"
        echo "    $SCRIPT_DIR/claude-settings-hooks.json"
        echo "  into: $SETTINGS_FILE"
    fi
else
    # Create new settings file with hooks
    cp "$SCRIPT_DIR/claude-settings-hooks.json" "$SETTINGS_FILE"
    echo "  Created new settings file with hooks"
fi

echo ""
echo "Installation complete!"
echo ""
echo "The following hooks are now active:"
echo "  - UserPromptSubmit: Track when user sends input"
echo "  - PreToolUse: Track when Claude starts using a tool"
echo "  - PostToolUse: Track when Claude finishes using a tool"
echo "  - Stop: Track when Claude finishes responding"
echo "  - SessionStart: Track session start"
echo "  - SessionEnd: Track session end"
echo "  - Notification (permission_prompt): Track when Claude asks for permission"
echo ""
echo "Events will be written to: ~/.claude/chat-sessions-events.jsonl"
