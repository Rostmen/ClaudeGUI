#!/bin/bash
# Tenvy Hook Handler
# Receives Claude Code hook events and writes them to a file for the app to monitor

EVENTS_FILE="${HOME}/.claude/chat-sessions-events.jsonl"

# Ensure events directory exists
mkdir -p "$(dirname "$EVENTS_FILE")"

# Read JSON input from stdin
INPUT=$(cat)

# Extract fields from input
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')
# For permission prompts, extract the message/details
NOTIFICATION_MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')
# Also capture tool input for context (file path, command, etc.)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // null')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Terminal ID from Tenvy — enables reliable session ID mapping
TERMINAL_ID="${TENVY_SESSION_ID:-}"

# Skip if no session ID
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# Determine state based on hook event
case "$HOOK_EVENT" in
    "UserPromptSubmit")
        STATE="processing"
        ;;
    "PreToolUse")
        STATE="thinking"
        ;;
    "PostToolUse")
        STATE="thinking"
        ;;
    "Stop")
        STATE="waiting"
        ;;
    "SessionStart")
        STATE="started"
        ;;
    "SessionEnd")
        STATE="ended"
        ;;
    "PermissionRequest")
        STATE="waitingPermission"
        ;;
    "Notification")
        # Notification fires for multiple types — only map permission_prompt as permission needed
        if [ "$NOTIFICATION_TYPE" = "permission_prompt" ]; then
            STATE="waitingPermission"
        elif [ "$NOTIFICATION_TYPE" = "idle_prompt" ]; then
            STATE="waiting"
        else
            # auth_success, elicitation_dialog, etc — not a state change we track
            exit 0
        fi
        ;;
    *)
        STATE="unknown"
        ;;
esac

# Build output JSON (compact single-line with -c flag for JSONL format)
OUTPUT=$(jq -cn \
    --arg session_id "$SESSION_ID" \
    --arg event "$HOOK_EVENT" \
    --arg state "$STATE" \
    --arg cwd "$CWD" \
    --arg tool "$TOOL_NAME" \
    --arg message "$NOTIFICATION_MESSAGE" \
    --argjson tool_input "$TOOL_INPUT" \
    --arg timestamp "$TIMESTAMP" \
    --arg terminal_id "$TERMINAL_ID" \
    '{
        session_id: $session_id,
        event: $event,
        state: $state,
        cwd: $cwd,
        tool: (if $tool == "" then null else $tool end),
        message: (if $message == "" then null else $message end),
        tool_input: $tool_input,
        timestamp: $timestamp,
        terminal_id: (if $terminal_id == "" then null else $terminal_id end)
    }')

# Append to events file
echo "$OUTPUT" >> "$EVENTS_FILE"

# Keep file size manageable - keep last 1000 lines
if [ -f "$EVENTS_FILE" ]; then
    LINES=$(wc -l < "$EVENTS_FILE")
    if [ "$LINES" -gt 1000 ]; then
        tail -500 "$EVENTS_FILE" > "${EVENTS_FILE}.tmp"
        mv "${EVENTS_FILE}.tmp" "$EVENTS_FILE"
    fi
fi

# Exit successfully
exit 0
