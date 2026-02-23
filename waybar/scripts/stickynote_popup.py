#!/usr/bin/env python3
"""
Sticky Note Popup für Waybar auf Hyprland/Wayland
Nutzt gtk-layer-shell für echtes Wayland-Layer-Popup.

Deps: sudo pacman -S gtk-layer-shell python-gobject
"""

import gi
import os
import subprocess

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, Gdk, GtkLayerShell, GLib

NOTE_FILE = os.path.expanduser("~/.config/waybar/sticky_note.txt")

CSS = b"""
window {
    background-color: rgba(15, 61, 61, 0.7);
    border: 1px solid rgba(212, 175, 55, 0.6);
    border-radius: 12px;
}
textview {
    background-color: transparent;
    color: #d4af37;
    font-family: JetBrainsMono, monospace;
    font-size: 14px;
    padding: 12px;
}
textview text {
    background-color: transparent;
    color: #d4af37;
}
#header {
    background-color: rgba(26, 92, 92, 0.8);
    border-radius: 12px 12px 0 0;
    padding: 8px 12px;
    border-bottom: 1px solid rgba(212, 175, 55, 0.4);
}
#header label {
    color: #d4af37;
    font-size: 13px;
    font-weight: bold;
}
button {
    background: none;
    border: none;
    color: #a68528;
    font-size: 14px;
    padding: 0 4px;
    min-height: 0;
    min-width: 0;
}
button:hover {
    color: #cc3333;
}
"""


def load_note():
    if os.path.exists(NOTE_FILE):
        with open(NOTE_FILE, "r") as f:
            return f.read()
    return ""


def save_note(text):
    os.makedirs(os.path.dirname(NOTE_FILE), exist_ok=True)
    with open(NOTE_FILE, "w") as f:
        f.write(text)


def get_cursor_x():
    """Cursor-X-Position via hyprctl (funktioniert auf Hyprland/Wayland)."""
    try:
        out = subprocess.check_output(["hyprctl", "cursorpos"], text=True).strip()
        # Format: "x, y"
        x = int(out.split(",")[0].strip())
        return x
    except Exception:
        return 0


class StickyNotePopup(Gtk.Window):
    def __init__(self):
        super().__init__()

        # --- GTK Layer Shell: echtes Wayland-Popup ---
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        # Nur oben ankern → GTK zentriert horizontal automatisch
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 10)
        # Tastatur-Eingabe erlauben
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)

        self.set_default_size(600, 450)
        self.set_size_request(600, 450)

        # CSS
        screen = self.get_screen()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # --- Layout ---
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)

        # Titelzeile
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header.set_name("header")
        title = Gtk.Label(label="📌 Sticky Note")
        title.set_halign(Gtk.Align.START)
        title.set_hexpand(True)
        hint = Gtk.Label(label="Esc = schließen")
        hint.get_style_context()
        close_btn = Gtk.Button(label="✕")
        close_btn.connect("clicked", lambda _: self.close_and_save())
        header.pack_start(title, True, True, 0)
        header.pack_end(close_btn, False, False, 0)
        header.pack_end(hint, False, False, 8)
        box.pack_start(header, False, False, 0)

        # Textbereich
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_margin_start(4)
        scroll.set_margin_end(4)
        scroll.set_margin_top(4)
        scroll.set_margin_bottom(4)

        self.textview = Gtk.TextView()
        self.textview.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.textview.set_accepts_tab(False)
        self.buffer = self.textview.get_buffer()
        self.buffer.set_text(load_note())

        # Cursor ans Ende
        self.buffer.place_cursor(self.buffer.get_end_iter())

        scroll.add(self.textview)
        box.pack_start(scroll, True, True, 0)

        # Events
        self.connect("key-press-event", self.on_key_press)

        self.show_all()
        GLib.idle_add(self._grab_focus)

    def _grab_focus(self):
        self.textview.grab_focus()
        return False

    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close_and_save()
        return False

    def close_and_save(self):
        start = self.buffer.get_start_iter()
        end = self.buffer.get_end_iter()
        save_note(self.buffer.get_text(start, end, False))
        Gtk.main_quit()


if __name__ == "__main__":
    app = StickyNotePopup()
    Gtk.main()
