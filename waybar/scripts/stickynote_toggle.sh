#!/bin/bash
# Toggle: läuft das Popup? → schließen, sonst → öffnen
if pgrep -f "stickynote_popup.py" > /dev/null; then
    pkill -f "stickynote_popup.py"
else
    python3 ~/.config/waybar/scripts/stickynote_popup.py
fi
