#!/bin/bash
wallpaper="$1"
filename=$(basename "$wallpaper")

declare -A wallpaper_colors=(
    ["Herbst.png"]="#800000"
    ["Background.png"]="#151B54"
)

awww img "$wallpaper"

if [[ -n "${wallpaper_colors[$filename]}" ]]; then
    # Deine manuell festgelegte Farbe -> möglichst 1:1 als primary übernehmen
    matugen color hex "${wallpaper_colors[$filename]}" --type scheme-fidelity < /dev/null
else
    # Kein manueller Eintrag -> automatisch aus dem Bild generieren
    matugen image "$wallpaper" --source-color-index 0 --type scheme-content < /dev/null
fi
