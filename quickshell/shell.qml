import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "widgets"
import "sidebar"

Scope {
    id: root

    property int barHeight: 32
    property int marginSide: 38
    property int marginTop: 10
    property int cornerRadius: 12
    property int windowGap: 16    // niri's default gap around tiled windows
    property int ccWidth: 320
    property int notesWidth: 500

    // Sidebar geometry: a floating dock capsule on the left screen edge that
    // slides out when the mouse is near. edgeTriggerWidth is the collapsed
    // surface: a slim trigger strip at the very edge. Its hover zone doubles
    // as its input region, so every px of it also swallows clicks — keep it
    // thin, it only has to catch a pointer flicked to the edge. The rest of
    // the near-edge area is free for clicks to the window underneath.
    property int sidebarWidth: 52
    property int edgeTriggerWidth: 8
    property int sidebarGap: 8       // floating gap between screen edge and pill
    property int sidebarVMargin: 10  // max top/bottom gap of the sidebar pill

    property color barColor: "#800000"
    property color textColor: "#f2ece0"
    property color ccBgColor: "#8d1d1d"
    property color accentColor: "#e0b45c"
    property color dimColor: Qt.rgba(1, 1, 1, 0.12)
    property color dangerColor: "#C34043"
    property string iconFont: "AtkynsonMono Nerd Font"

    // Bookshelf popup palette (BookPicker + its form/file browser only).
    // window_bg_color / error_* mirror the user's GTK theme; accent and all
    // text are plain white (white highlighted boxes, white text everywhere).
    property color shelfBgColor: "#00190f"
    property color shelfAccentColor: "#ffffff"    // highlighted boxes: primary buttons, focus borders
    property color shelfAccentFgColor: "#00190f"  // text on the white accent boxes
    property color shelfFgColor: "#ffffff"
    property color shelfErrorColor: "#C34043"
    property color shelfErrorFgColor: "#ffffff"

    // Excalidraw popup palette (whiteboard widget only): excalidraw.com's
    // light chrome, dark ink and purple selection accent.
    property color exBgColor: "#f8f9fa"
    property color exFgColor: "#1e1e1e"
    property color exAccentColor: "#6965db"

    // Exposed so widgets can close each other's popups.
    property var ccPopup: controlCenter.popup
    property var notesPopup: notesWidget.popup
    property var bookPopup: bookPicker.popup
    property var spotifyPopup: spotifyWidget.popup
    property var excalidrawPopup: excalidrawWidget.popup

    SidebarWidget { shell: root }

    BookPicker { id: bookPicker; shell: root }

    SpotifyWidget { id: spotifyWidget; shell: root }

    ExcalidrawWidget { id: excalidrawWidget; shell: root }

    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        implicitHeight: root.barHeight + root.marginTop
        exclusiveZone: root.barHeight + root.marginTop
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-bar-red-floating"
        // Allow anchored popups to take keyboard focus when requested.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Item {
            anchors.fill: parent

            MultiEffect {
                source: pill
                anchors.fill: pill
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.35
                shadowBlur: 0.6
                shadowVerticalOffset: 4
                z: -1
            }

            Rectangle {
                id: pill
                anchors {
                    left: parent.left; right: parent.right; top: parent.top
                    leftMargin: root.marginSide; rightMargin: root.marginSide; topMargin: root.marginTop
                }
                height: root.barHeight
                radius: root.cornerRadius
                color: root.barColor

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Item {
                        Layout.preferredWidth: rightCluster.implicitWidth
                        Layout.preferredHeight: root.barHeight
                        RowLayout {
                            id: leftCluster
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            WorkspaceWidget { shell: root }
                            BluetoothWidget { shell: root }
                            NotesWidget {
                                id: notesWidget
                                shell: root
                                popupWidth: root.notesWidth
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        id: rightCluster
                        spacing: 8
                        ControlCenter { id: controlCenter; shell: root }
                        ClockWidget { shell: root }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "notes"

        function toggle() {
            notesWidget.toggle()
        }
    }

    IpcHandler {
        target: "bookshelfs"

        function toggle() {
            bookPicker.toggle()
        }
    }

    IpcHandler {
        target: "spotify"

        function toggle() {
            spotifyWidget.toggle()
        }
    }

    IpcHandler {
        target: "excalidraw"

        function toggle() {
            excalidrawWidget.toggle()
        }
    }
}
