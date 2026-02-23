#!/bin/bash

NOTE_FILE="$HOME/.config/waybar/sticky_note.txt"
touch "$NOTE_FILE"

# Waybar fragt per exec nach dem aktuellen Status → JSON ausgeben
if [ -s "$NOTE_FILE" ]; then
    echo '{"text":"","tooltip":"Notiz vorhanden – klicken zum Bearbeiten","class":"has-note"}'
else
    echo '{"text":"","tooltip":"Klicken zum Schreiben","class":"empty"}'
fi
