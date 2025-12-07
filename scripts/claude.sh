#!/bin/bash
# Launcher for Claude Code in the ROCm workspace.
# Ensures the correct Python venv is active before launching.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

# Deactivate any active Python venv
if [[ -n "$VIRTUAL_ENV" ]]; then
    deactivate 2>/dev/null || true
fi

# Activate the workspace venv
if [[ -f "$WORKSPACE_DIR/venv/bin/activate" ]]; then
    source "$WORKSPACE_DIR/venv/bin/activate"
else
    echo "Error: venv not found at $WORKSPACE_DIR/venv" >&2
    exit 1
fi

# Launch Claude in the workspace directory
cd "$WORKSPACE_DIR"
exec claude "$@"
