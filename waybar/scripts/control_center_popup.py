#!/usr/bin/env python3
"""
Control Center Popup for Waybar on Hyprland/Wayland
Uses gtk-layer-shell for a true Wayland layer popup.
"""

import gi
import os
import subprocess
import threading
import time

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, Gdk, GtkLayerShell, GLib

CSS = b"""
window {
    background-color: rgba(15, 61, 61, 0.7);
    border: 1px solid rgba(212, 175, 55, 0.6);
    border-radius: 12px;
}
#header {
    background-color: rgba(26, 92, 92, 0.8);
    border-radius: 12px 12px 0 0;
    padding: 10px 16px;
    border-bottom: 1px solid rgba(212, 175, 55, 0.4);
}
#header label {
    color: #d4af37;
    font-size: 14px;
    font-weight: bold;
}
.control-row {
    padding: 12px 16px;
}
.control-label {
    color: #d4af37;
    font-size: 14px;
    margin-right: 12px;
}
scale.horizontal {
    padding: 0;
    margin: 0;
}
scale highlight {
    background-color: #d4af37;
    border-radius: 10px;
}
scale trough {
    background-color: rgba(212, 175, 55, 0.2);
    border-radius: 10px;
    min-height: 8px;
}
scale slider {
    min-width: 14px;
    min-height: 14px;
    background-color: #a68528;
    border-radius: 50%;
    margin: -3px;
}
button.toggle-btn {
    background-color: rgba(212, 175, 55, 0.1);
    color: #d4af37;
    border: 1px solid rgba(212, 175, 55, 0.3);
    border-radius: 50px;
    padding: 8px 16px;
    font-size: 14px;
}
button.toggle-btn:hover {
    background-color: rgba(212, 175, 55, 0.2);
}
button.toggle-btn.active {
    background-color: rgba(212, 175, 55, 0.3);
    color: #d4af37;
    border-color: #d4af37;
}
button.power-btn {
    background-color: rgba(204, 51, 51, 0.2);
    color: #cc3333;
    border: 1px solid rgba(204, 51, 51, 0.4);
    border-radius: 50px;
    padding: 8px 16px;
    font-size: 14px;
    font-weight: bold;
}
button.power-btn:hover {
    background-color: rgba(204, 51, 51, 0.4);
}
button.network-btn {
    background-color: rgba(51, 204, 102, 0.1);
    color: #33cc66;
    border: 1px solid rgba(51, 204, 102, 0.3);
    border-radius: 50px;
    padding: 8px 16px;
    font-size: 14px;
}
button.network-btn:hover {
    background-color: rgba(51, 204, 102, 0.2);
}
button.network-btn.active {
    background-color: rgba(51, 204, 102, 0.3);
    color: #33cc66;
    border-color: #33cc66;
}
.bt-menu {
    background-color: rgba(26, 92, 92, 0.8);
    border-radius: 8px;
    padding: 8px;
    margin-top: 8px;
}
.bt-list-header {
    color: #d4af37;
    font-size: 13px;
    font-weight: bold;
    margin-top: 8px;
    margin-bottom: 4px;
}
.bt-device-row {
    padding: 6px;
    border-radius: 6px;
}
.bt-device-row:hover {
    background-color: rgba(212, 175, 55, 0.1);
}
.bt-device-name {
    color: #d4af37;
    font-size: 13px;
}
.bt-device-status {
    color: #a68528;
    font-size: 11px;
}
.bt-device-btn {
    background-color: rgba(212, 175, 55, 0.1);
    color: #d4af37;
    border: none;
    border-radius: 4px;
    padding: 4px 8px;
    font-size: 12px;
}
.bt-device-btn:hover {
    background-color: rgba(212, 175, 55, 0.2);
}
.bt-device-btn.connected {
    background-color: rgba(212, 175, 55, 0.3);
    color: #000000;
}
"""

class ControlCenterPopup(Gtk.Window):
    def __init__(self):
        super().__init__()

        # GTK Layer Shell setup
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 10)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 10)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)

        self.set_default_size(320, -1)
        self.set_size_request(320, -1)

        # Apply CSS
        screen = self.get_screen()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # Main Layout
        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(self.main_box)

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header.set_name("header")
        title = Gtk.Label(label="⚙ Control Center")
        title.set_halign(Gtk.Align.START)
        header.pack_start(title, True, True, 0)
        self.main_box.pack_start(header, False, False, 0)

        # Content Box
        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        content_box.set_margin_start(16)
        content_box.set_margin_end(16)
        content_box.set_margin_top(16)
        content_box.set_margin_bottom(16)
        self.main_box.pack_start(content_box, True, True, 0)

        # Brightness Section
        bright_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        bright_label = Gtk.Label(label="󰃠 ")
        bright_label.get_style_context().add_class("control-label")
        self.bright_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 1, 100, 1)
        self.bright_scale.set_hexpand(True)
        self.bright_scale.set_draw_value(False)
        self.bright_scale.connect("value-changed", self.on_brightness_changed)
        bright_box.pack_start(bright_label, False, False, 0)
        bright_box.pack_start(self.bright_scale, True, True, 0)
        content_box.pack_start(bright_box, False, False, 0)

        # Audio Section
        audio_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        audio_label = Gtk.Label(label=" ")
        audio_label.get_style_context().add_class("control-label")
        self.audio_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.audio_scale.set_hexpand(True)
        self.audio_scale.set_draw_value(False)
        self.audio_scale.connect("value-changed", self.on_audio_changed)
        audio_box.pack_start(audio_label, False, False, 0)
        audio_box.pack_start(self.audio_scale, True, True, 0)
        content_box.pack_start(audio_box, False, False, 0)

        # Buttons Box
        buttons_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        content_box.pack_start(buttons_box, False, False, 8)

        # Bluetooth Button
        self.bt_btn = Gtk.Button(label=" Bluetooth")
        self.bt_btn.get_style_context().add_class("toggle-btn")
        self.bt_btn.connect("clicked", self.on_bt_toggle)
        self.bt_btn.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.bt_btn.connect("button-press-event", self.on_bt_button_press)
        buttons_box.pack_start(self.bt_btn, True, True, 0)
        
        # Network Button
        self.net_btn = Gtk.Button(label=" Network")
        self.net_btn.get_style_context().add_class("network-btn")
        self.net_btn.connect("clicked", self.on_net_toggle)
        self.net_btn.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.net_btn.connect("button-press-event", self.on_net_button_press)
        buttons_box.pack_start(self.net_btn, True, True, 0)

        # Power Button
        power_btn = Gtk.Button(label=" Power")
        power_btn.get_style_context().add_class("power-btn")
        power_btn.connect("clicked", self.on_power_off)
        buttons_box.pack_start(power_btn, True, True, 0)

        # Bluetooth Sub-Menu (Hidden by default)
        self.bt_menu = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.bt_menu.get_style_context().add_class("bt-menu")
        self.bt_menu.set_no_show_all(True)
        content_box.pack_start(self.bt_menu, False, False, 0)
        
        # Paired Devices Header
        paired_lbl = Gtk.Label(label="Ihre Geräte")
        paired_lbl.set_halign(Gtk.Align.START)
        paired_lbl.get_style_context().add_class("bt-list-header")
        self.bt_menu.pack_start(paired_lbl, False, False, 0)
        
        # Paired Devices ListBox
        self.paired_list = Gtk.ListBox()
        self.paired_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.bt_menu.pack_start(self.paired_list, False, False, 0)
        
        # New Devices Header & Scan Button Box
        new_dev_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        new_lbl = Gtk.Label(label="Neue Geräte")
        new_lbl.set_halign(Gtk.Align.START)
        new_lbl.get_style_context().add_class("bt-list-header")
        new_dev_box.pack_start(new_lbl, True, True, 0)
        
        self.scan_btn = Gtk.Button(label="Suchen")
        self.scan_btn.get_style_context().add_class("bt-device-btn")
        self.scan_btn.connect("clicked", self.on_bt_scan)
        new_dev_box.pack_start(self.scan_btn, False, False, 0)
        
        self.bt_menu.pack_start(new_dev_box, False, False, 0)
        
        # New Devices ListBox
        self.new_list = Gtk.ListBox()
        self.new_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.bt_menu.pack_start(self.new_list, False, False, 0)

        # Network Sub-Menu (Hidden by default)
        self.net_menu = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.net_menu.get_style_context().add_class("bt-menu")
        self.net_menu.set_no_show_all(True)
        content_box.pack_start(self.net_menu, False, False, 0)

        # Network Header & Scan Button Box
        net_dev_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        net_lbl = Gtk.Label(label="WLAN Netzwerke")
        net_lbl.set_halign(Gtk.Align.START)
        net_lbl.get_style_context().add_class("bt-list-header")
        net_dev_box.pack_start(net_lbl, True, True, 0)

        self.net_scan_btn = Gtk.Button(label="Suchen")
        self.net_scan_btn.get_style_context().add_class("bt-device-btn")
        self.net_scan_btn.connect("clicked", self.on_net_scan)
        net_dev_box.pack_start(self.net_scan_btn, False, False, 0)
        
        self.net_menu.pack_start(net_dev_box, False, False, 0)

        # Networks ListBox
        self.networks_list = Gtk.ListBox()
        self.networks_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.net_menu.pack_start(self.networks_list, False, False, 0)

        # Initialize Update Flags
        self.updating_audio = False
        self.updating_bright = False
        self.net_showing_alt = False

        # Initial values
        self.update_initial_values()

        self.connect("key-press-event", self.on_key_press)
        
        # Listen for focus-out to close popup
        self.connect("focus-out-event", self.on_focus_out)

        self.show_all()
        GLib.idle_add(self._grab_focus)

    def _grab_focus(self):
        self.present()
        return False

    def get_max_brightness(self):
        try:
            return int(subprocess.check_output(["brightnessctl", "m"], text=True).strip())
        except:
            return 100 # Default fallback if error

    def update_initial_values(self):
        # Audio Update
        try:
            out = subprocess.check_output(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], text=True).strip()
            # typical format: "Volume: 0.85"
            if "Volume:" in out:
                vol_str = out.split()[1]
                self.updating_audio = True
                self.audio_scale.set_value(float(vol_str) * 100)
                self.updating_audio = False
        except:
            pass
            
        # Brightness Update
        try:
            current = int(subprocess.check_output(["brightnessctl", "g"], text=True).strip())
            max_b = self.get_max_brightness()
            percent = (current / max_b) * 100
            self.updating_bright = True
            self.bright_scale.set_value(percent)
            self.updating_bright = False
        except:
            pass
            
        # Bluetooth Update
        self.update_bt_status()
        
        # Network Update
        self.update_net_status()

    def update_bt_status(self):
        try:
            # check if blocked
            out = subprocess.check_output(["rfkill", "list", "bluetooth"], text=True)
            if "Soft blocked: yes" in out:
                self.bt_btn.get_style_context().remove_class("active")
                self.bt_active = False
            else:
                self.bt_btn.get_style_context().add_class("active")
                self.bt_active = True
        except:
            self.bt_active = False

    def update_net_status(self):
        try:
            # check if wifi is enabled
            radio = subprocess.check_output(["nmcli", "radio", "wifi"], text=True)
            self.net_active = "enabled" in radio
            
            if self.net_active:
                self.net_btn.get_style_context().add_class("active")
                # Get current connection info
                out = subprocess.check_output(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "dev", "wifi"], text=True)
                ssid = ""
                signal = ""
                for line in out.strip().split('\n'):
                    parts = line.split(":")
                    if len(parts) >= 3 and parts[0] == "*":
                        ssid = parts[1]
                        signal = parts[2]
                        break
                
                if self.net_showing_alt:
                    # format-alt = {essid}
                    if ssid:
                        self.net_btn.set_label(f"{ssid}")
                    else:
                        self.net_btn.set_label("Disconnected")
                else:
                    # format =  {signalStrength}%
                    if ssid:
                        self.net_btn.set_label(f" {signal}%")
                    else:
                        self.net_btn.set_label(" Disconnected")
            else:
                self.net_btn.get_style_context().remove_class("active")
                self.net_btn.set_label(" Off")
        except:
            self.net_active = False

    def on_audio_changed(self, scale):
        if self.updating_audio:
            return
        val = scale.get_value()
        vol = val / 100.0
        subprocess.Popen(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{vol:.2f}"], stdout=subprocess.DEVNULL)

    def on_brightness_changed(self, scale):
        if self.updating_bright:
            return
        val = scale.get_value()
        subprocess.Popen(["brightnessctl", "set", f"{int(val)}%"], stdout=subprocess.DEVNULL)

    def on_bt_toggle(self, btn):
        if self.bt_active:
            subprocess.Popen(["rfkill", "block", "bluetooth"])
        else:
            subprocess.Popen(["rfkill", "unblock", "bluetooth"])
        
        # Debounce the UI update
        GLib.timeout_add(300, self.delayed_bt_update)
        
    def delayed_bt_update(self):
        self.update_bt_status()
        return False

    def on_net_toggle(self, btn):
        if self.net_active:
            subprocess.Popen(["nmcli", "radio", "wifi", "off"])
        else:
            subprocess.Popen(["nmcli", "radio", "wifi", "on"])
        
        # Debounce the UI update
        GLib.timeout_add(300, self.delayed_net_update)

    def delayed_net_update(self):
        self.update_net_status()
        return False

    def on_bt_button_press(self, widget, event):
        if event.button == 3: # Right click
            if self.net_menu.get_visible():
                self.net_menu.hide()
            self.main_box.set_size_request(-1, -1)
            if self.bt_menu.get_visible():
                self.bt_menu.hide()
            else:
                self.bt_menu.show_all()
                self.bt_menu.show()
                self.load_paired_devices()
            return True
        return False
        
    def on_net_button_press(self, widget, event):
        if event.button == 3: # Right click: format-alt toggle
            self.net_showing_alt = not self.net_showing_alt
            self.update_net_status()
            return True
        elif event.button == 2: # Middle click: open menu
            if self.bt_menu.get_visible():
                self.bt_menu.hide()
            self.main_box.set_size_request(-1, -1)
            if self.net_menu.get_visible():
                self.net_menu.hide()
            else:
                self.net_menu.show_all()
                self.net_menu.show()
                self.load_networks()
            return True
        return False
        
    def _clear_listbox(self, listbox):
        for row in listbox.get_children():
            listbox.remove(row)
            
    def load_paired_devices(self):
        self._clear_listbox(self.paired_list)
        threading.Thread(target=self._fetch_paired_devices, daemon=True).start()
        
    def _fetch_paired_devices(self):
        try:
            out = subprocess.check_output(["bluetoothctl", "devices", "Paired"], text=True)
            devices = []
            for line in out.strip().split('\n'):
                if line.startswith("Device "):
                    parts = line.split(" ", 2)
                    if len(parts) >= 3:
                        mac, name = parts[1], parts[2]
                        # Check connection status
                        info_out = subprocess.check_output(["bluetoothctl", "info", mac], text=True)
                        connected = "Connected: yes" in info_out
                        devices.append((mac, name, connected))
                        
            GLib.idle_add(self._populate_paired_devices, devices)
        except Exception as e:
            print(f"Error fetching BT devices: {e}")

    def _populate_paired_devices(self, devices):
        self._clear_listbox(self.paired_list)
        if not devices:
            lbl = Gtk.Label(label="Keine Geräte")
            lbl.set_halign(Gtk.Align.START)
            self.paired_list.add(lbl)
            self.paired_list.show_all()
            return

        for mac, name, connected in devices:
            row = Gtk.ListBoxRow()
            row.get_style_context().add_class("bt-device-row")
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            
            vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            name_lbl = Gtk.Label(label=name)
            name_lbl.set_halign(Gtk.Align.START)
            name_lbl.get_style_context().add_class("bt-device-name")
            vbox.pack_start(name_lbl, False, False, 0)
            
            box.pack_start(vbox, True, True, 0)
            
            btn = Gtk.Button(label="Trennen" if connected else "Verbinden")
            btn.get_style_context().add_class("bt-device-btn")
            if connected:
                btn.get_style_context().add_class("connected")
            btn.connect("clicked", self.on_device_action, mac, connected)
            box.pack_start(btn, False, False, 0)
            
            row.add(box)
            self.paired_list.add(row)
            
        self.paired_list.show_all()
        
    def on_device_action(self, btn, mac, currently_connected):
        btn.set_sensitive(False)
        btn.set_label("...")
        action = "disconnect" if currently_connected else "connect"
        threading.Thread(target=self._do_device_action, args=(action, mac), daemon=True).start()
        
    def _do_device_action(self, action, mac):
        try:
            subprocess.run(["bluetoothctl", action, mac], capture_output=True)
        except:
            pass
        GLib.idle_add(self.load_paired_devices)
        
    def on_bt_scan(self, btn):
        self.scan_btn.set_sensitive(False)
        self.scan_btn.set_label("Suche...")
        self._clear_listbox(self.new_list)
        threading.Thread(target=self._do_scan, daemon=True).start()
        
    def _do_scan(self):
        try:
            # Start scan
            subprocess.Popen(["bluetoothctl", "scan", "on"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(5) # Scan for 5 seconds
            subprocess.Popen(["bluetoothctl", "scan", "off"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            # Get all devices
            out = subprocess.check_output(["bluetoothctl", "devices"], text=True)
            paired_out = subprocess.check_output(["bluetoothctl", "devices", "Paired"], text=True)
            
            paired_macs = set()
            for line in paired_out.strip().split('\n'):
                if line.startswith("Device "):
                    parts = line.split(" ", 2)
                    if len(parts) >= 2:
                        paired_macs.add(parts[1])
                        
            new_devices = []
            for line in out.strip().split('\n'):
                if line.startswith("Device "):
                    parts = line.split(" ", 2)
                    if len(parts) >= 3:
                        mac, name = parts[1], parts[2]
                        if mac not in paired_macs and name and "-" not in name: # naive filter for unnamed devices
                             new_devices.append((mac, name))
                             
            GLib.idle_add(self._populate_new_devices, new_devices)
        except Exception as e:
            print(f"Scan error: {e}")
            GLib.idle_add(self._reset_scan_btn)

    def _reset_scan_btn(self):
        self.scan_btn.set_sensitive(True)
        self.scan_btn.set_label("Suchen")

    def _populate_new_devices(self, devices):
        self._reset_scan_btn()
        self._clear_listbox(self.new_list)
        
        if not devices:
            lbl = Gtk.Label(label="Nichts gefunden")
            lbl.set_halign(Gtk.Align.START)
            self.new_list.add(lbl)
            self.new_list.show_all()
            return
            
        for mac, name in devices[:5]: # limit to top 5
            row = Gtk.ListBoxRow()
            row.get_style_context().add_class("bt-device-row")
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            
            name_lbl = Gtk.Label(label=name)
            name_lbl.set_halign(Gtk.Align.START)
            name_lbl.get_style_context().add_class("bt-device-name")
            box.pack_start(name_lbl, True, True, 0)
            
            btn = Gtk.Button(label="Koppeln")
            btn.get_style_context().add_class("bt-device-btn")
            btn.connect("clicked", self.on_device_pair, mac)
            box.pack_start(btn, False, False, 0)
            
            row.add(box)
            self.new_list.add(row)
            
        self.new_list.show_all()
        
    def on_device_pair(self, btn, mac):
        btn.set_sensitive(False)
        btn.set_label("...")
        threading.Thread(target=self._do_device_pair, args=(mac,), daemon=True).start()
        
    def _do_device_pair(self, mac):
        try:
            subprocess.run(["bluetoothctl", "pair", mac], capture_output=True)
            subprocess.run(["bluetoothctl", "trust", mac], capture_output=True)
            subprocess.run(["bluetoothctl", "connect", mac], capture_output=True)
        except:
            pass
        GLib.idle_add(self.load_paired_devices)
        GLib.idle_add(self._clear_listbox, self.new_list)

    def load_networks(self):
        self._clear_listbox(self.networks_list)
        threading.Thread(target=self._fetch_networks, daemon=True).start()
        
    def _fetch_networks(self):
        try:
            out = subprocess.check_output(
                ["nmcli", "-t", "-f", "IN-USE,BSSID,SSID,SIGNAL", "dev", "wifi"], text=True
            )
            networks = []
            seen_ssids = set()
            for line in out.strip().split('\n'):
                if line:
                    parts = line.split(":")
                    if len(parts) >= 4:
                        in_use, bssid, ssid, signal = parts[0], parts[1], parts[2], parts[3]
                        if ssid and ssid not in seen_ssids:
                            seen_ssids.add(ssid)
                            connected = (in_use == "*")
                            networks.append((ssid, bssid, int(signal), connected))
                            
            GLib.idle_add(self._populate_networks, networks)
        except Exception as e:
            print(f"Error fetching networks: {e}")

    def _populate_networks(self, networks):
        self._clear_listbox(self.networks_list)
        if not networks:
            lbl = Gtk.Label(label="Keine Netzwerke")
            lbl.set_halign(Gtk.Align.START)
            self.networks_list.add(lbl)
            self.networks_list.show_all()
            return

        for ssid, bssid, signal, connected in networks[:10]:
            row = Gtk.ListBoxRow()
            row.get_style_context().add_class("bt-device-row")
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            
            vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            name_lbl = Gtk.Label(label=ssid)
            name_lbl.set_halign(Gtk.Align.START)
            name_lbl.get_style_context().add_class("bt-device-name")
            vbox.pack_start(name_lbl, False, False, 0)
            
            sig_lbl = Gtk.Label(label=f"Signal: {signal}%")
            sig_lbl.set_halign(Gtk.Align.START)
            sig_lbl.get_style_context().add_class("bt-device-status")
            vbox.pack_start(sig_lbl, False, False, 0)
            
            box.pack_start(vbox, True, True, 0)
            
            btn = Gtk.Button(label="Trennen" if connected else "Verbinden")
            btn.get_style_context().add_class("bt-device-btn")
            if connected:
                btn.get_style_context().add_class("connected")
            btn.connect("clicked", self.on_net_connect, bssid, connected)
            box.pack_start(btn, False, False, 0)
            
            row.add(box)
            self.networks_list.add(row)
            
        self.networks_list.show_all()

    def on_net_scan(self, btn):
        self.net_scan_btn.set_sensitive(False)
        self.net_scan_btn.set_label("Suche...")
        threading.Thread(target=self._do_net_scan, daemon=True).start()

    def _do_net_scan(self):
        try:
            subprocess.run(["nmcli", "dev", "wifi", "rescan"], capture_output=True)
            time.sleep(2)
        except:
            pass
        GLib.idle_add(self._reset_net_scan_btn)
        GLib.idle_add(self.load_networks)

    def _reset_net_scan_btn(self):
        self.net_scan_btn.set_sensitive(True)
        self.net_scan_btn.set_label("Suchen")

    def on_net_connect(self, btn, bssid, currently_connected):
        btn.set_sensitive(False)
        btn.set_label("...")
        action = "disconnect" if currently_connected else "connect"
        threading.Thread(target=self._do_net_connect, args=(action, bssid), daemon=True).start()
        
    def _do_net_connect(self, action, bssid):
        try:
            if action == "disconnect":
                # Get the active connection name for this BSSID (rough approach, normally you disconnect the device or connection name)
                # It's better to just disconnect the wifi device
                subprocess.run(["nmcli", "dev", "disconnect", "wlan0"], capture_output=True) 
            else:
                # Requires password if not already saved, which is tricky in GTK without a prompt.
                # Assumes saved or open network for now.
                subprocess.run(["nmcli", "dev", "wifi", "connect", bssid], capture_output=True)
        except:
            pass
        time.sleep(1)
        GLib.idle_add(self.load_networks)

    def on_power_off(self, btn):
        subprocess.Popen(["systemctl", "poweroff"])
        self.close()

    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            Gtk.main_quit()
        return False

    def on_focus_out(self, widget, event):
        self.close()
        Gtk.main_quit()
        return False
        
    def close(self):
        Gtk.Window.close(self)
        Gtk.main_quit()

if __name__ == "__main__":
    app = ControlCenterPopup()
    Gtk.main()
