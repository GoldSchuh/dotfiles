#!/usr/bin/env bash

# Toggle script for Waybar control center

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
POPUP_SCRIPT="control_center_popup.py"

# Find if python process is running our script
PID=$(pgrep -f "python.*$POPUP_SCRIPT")

if [ -n "$PID" ]; then
    kill $PID
else
    # Start the GTK popup
    python3 "$SCRIPT_DIR/$POPUP_SCRIPT" &
fi
