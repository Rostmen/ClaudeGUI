#!/bin/bash
# Diagnostic script for ChatSessions hooks and process monitoring

echo "=== ChatSessions Diagnostics ==="
echo ""

# 1. Check jq
echo "1. Checking jq..."
if command -v jq &> /dev/null; then
    echo "   ✓ jq is installed: $(which jq)"
else
    echo "   ✗ jq is NOT installed - hooks will fail!"
    echo "     Install with: brew install jq"
fi
echo ""

# 2. Check Claude CLI
echo "2. Checking Claude CLI..."
CLAUDE_PATHS=(
    "$HOME/.claude/local/claude"
    "$HOME/.nvm/versions/node/*/bin/claude"
    "/usr/local/bin/claude"
    "/opt/homebrew/bin/claude"
)
FOUND_CLAUDE=""
for pattern in "${CLAUDE_PATHS[@]}"; do
    for path in $pattern; do
        if [ -x "$path" ]; then
            FOUND_CLAUDE="$path"
            break 2
        fi
    done
done
if [ -n "$FOUND_CLAUDE" ]; then
    echo "   ✓ Claude found: $FOUND_CLAUDE"
else
    # Try which
    WHICH_CLAUDE=$(which claude 2>/dev/null)
    if [ -n "$WHICH_CLAUDE" ]; then
        echo "   ✓ Claude found via PATH: $WHICH_CLAUDE"
    else
        echo "   ✗ Claude CLI NOT found!"
    fi
fi
echo ""

# 3. Check hooks directory
echo "3. Checking hooks installation..."
HOOKS_DIR="$HOME/.claude/hooks"
HOOK_SCRIPT="$HOOKS_DIR/chat-sessions-hook.sh"
if [ -d "$HOOKS_DIR" ]; then
    echo "   ✓ Hooks directory exists: $HOOKS_DIR"
else
    echo "   ✗ Hooks directory NOT found: $HOOKS_DIR"
fi

if [ -f "$HOOK_SCRIPT" ]; then
    echo "   ✓ Hook script exists: $HOOK_SCRIPT"
    if [ -x "$HOOK_SCRIPT" ]; then
        echo "   ✓ Hook script is executable"
    else
        echo "   ✗ Hook script is NOT executable!"
        echo "     Fix with: chmod +x $HOOK_SCRIPT"
    fi
else
    echo "   ✗ Hook script NOT found!"
    echo "     Run install script from ChatSessions/Hooks/"
fi
echo ""

# 4. Check Claude settings
echo "4. Checking Claude settings..."
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    echo "   ✓ Settings file exists"

    # Check for hooks
    HOOK_COUNT=$(jq '.hooks | keys | length' "$SETTINGS_FILE" 2>/dev/null)
    if [ "$HOOK_COUNT" -gt 0 ] 2>/dev/null; then
        echo "   ✓ Hooks configured: $HOOK_COUNT hook types"

        # Check for Notification hook specifically
        if jq -e '.hooks.Notification' "$SETTINGS_FILE" > /dev/null 2>&1; then
            echo "   ✓ Notification hook configured"
        else
            echo "   ✗ Notification hook NOT configured - permission prompts won't be detected"
        fi
    else
        echo "   ✗ No hooks configured in settings!"
    fi
else
    echo "   ✗ Settings file NOT found: $SETTINGS_FILE"
fi
echo ""

# 5. Check events file
echo "5. Checking events file..."
EVENTS_FILE="$HOME/.claude/chat-sessions-events.jsonl"
if [ -f "$EVENTS_FILE" ]; then
    LINES=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
    echo "   ✓ Events file exists: $EVENTS_FILE"
    echo "   ✓ Contains $LINES events"

    # Show last event
    if [ "$LINES" -gt 0 ]; then
        echo "   Last event:"
        tail -1 "$EVENTS_FILE" | jq '.' 2>/dev/null || tail -1 "$EVENTS_FILE"
    fi
else
    echo "   ⚠ Events file does not exist yet (will be created on first hook event)"
fi
echo ""

# 6. Test hook script manually
echo "6. Testing hook script..."
if [ -x "$HOOK_SCRIPT" ]; then
    TEST_INPUT='{"session_id":"test-123","hook_event_name":"Stop","cwd":"/tmp"}'
    echo "$TEST_INPUT" | "$HOOK_SCRIPT"

    # Check if event was written
    if [ -f "$EVENTS_FILE" ]; then
        LAST_SESSION=$(tail -1 "$EVENTS_FILE" | jq -r '.session_id' 2>/dev/null)
        if [ "$LAST_SESSION" = "test-123" ]; then
            echo "   ✓ Hook script works correctly!"
            # Clean up test event
            head -n -1 "$EVENTS_FILE" > "${EVENTS_FILE}.tmp" && mv "${EVENTS_FILE}.tmp" "$EVENTS_FILE"
        else
            echo "   ✗ Hook script did not write event correctly"
        fi
    else
        echo "   ✗ Hook script did not create events file"
    fi
else
    echo "   ⚠ Cannot test - hook script not executable"
fi
echo ""

# 7. Check process permissions
echo "7. Checking process monitoring..."
if ps -A -o pid,comm > /dev/null 2>&1; then
    echo "   ✓ ps command works"
else
    echo "   ✗ ps command failed - process monitoring won't work"
fi
echo ""

echo "=== Diagnostics Complete ==="
echo ""
echo "If hooks are not installed, run:"
echo "  cd /path/to/ChatSessions/Hooks && ./install-hooks.sh"
echo ""
echo "If jq is missing, run:"
echo "  brew install jq"
