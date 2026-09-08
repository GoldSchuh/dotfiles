import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// A dock-style sidebar that only shows itself when the mouse is near the
// left screen edge and tucks away again when the mouse leaves it.
//
// There is no global cursor-position API in Quickshell, and on Wayland a
// surface's hover zone is its input region — a wide hover strip would also
// swallow every click inside it. So "mouse near" is implemented as a slim
// (edgeTriggerWidth px) always-present surface at the very left screen edge.
// A `mask` then limits the input region to the edge corridor plus the dock
// band, so while the dock is out, clicks above and below it (e.g. on app
// UI at the screen corner) pass through to the window underneath.
// When the strip detects the mouse, the surface width animates out to the
// full dock width; the expanded window itself also has hover detection, so
// it stays open while the mouse is over the dock (or while its popup is
// open).
//
// Palette comes from the shared shell theme (the same red bar colors), not
// hardcoded values.
PanelWindow {
    id: sidebar

    required property var shell

    readonly property bool pickerOpen: shell.bookPopup.visible
    readonly property bool spotifyOpen: shell.spotifyPopup.open
    readonly property bool exOpen: shell.excalidrawPopup.open
    // expanded is sticky: entering sets it instantly, leaving starts a short
    // debounce (hideTimer) before collapsing. Resizing a layer surface can
    // transiently drop containsMouse — collapsing immediately on that made
    // the dock flicker between expanded and collapsed.
    property bool expanded: false
    readonly property bool shown: expanded || pickerOpen || spotifyOpen || exOpen

    anchors { left: true; top: true; bottom: true }
    // Collapsed = just the trigger sliver at the edge, so only that sliver
    // can catch hover or clicks; the rest of the edge area is click-through
    // because no surface covers it.
    implicitWidth: shown ? shell.sidebarWidth + 2 * shell.sidebarGap : shell.edgeTriggerWidth
    exclusiveZone: 0    // floating overlay; does not push tiled windows
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-sidebar"

    // Clickable = union of:
    // - the trigger corridor along the full left edge (opens the dock at any
    //   screen height; same width as the collapsed surface),
    // - the dock band (edge gap + pill bounding box) so the dock itself is
    //   interactive and the pointer can travel from the edge onto it.
    // Everything else — above/below the open dock — passes clicks through.
    // While collapsed the window is corridor-sized anyway, so the band rect
    // is clipped away and the whole 8px surface is the trigger.
    mask: Region {
        Region {
            x: 0
            width: sidebar.shell.edgeTriggerWidth
            height: sidebar.height
        }
        Region {
            x: 0
            width: sidebar.shell.sidebarGap + sidebar.shell.sidebarWidth
            y: pill.y
            height: pill.height
        }
    }

    // Sliding out from the edge = animating the layer surface width.
    Behavior on implicitWidth {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Full-window hover catcher. It only reports hover inside the input
    // region (the mask above): the edge corridor and the dock band. Outside
    // those, hover and clicks belong to the window underneath. (Qt.NoButton
    // only stops this MouseArea from consuming clicks inside Qt.)
    MouseArea {
        id: hoverCatcher
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: {
            if (containsMouse) {
                hideTimer.stop()
                sidebar.expanded = true
            } else {
                hideTimer.restart()
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 250
        onTriggered: {
            if (!hoverCatcher.containsMouse && !sidebar.pickerOpen && !sidebar.spotifyOpen && !sidebar.exOpen)
                sidebar.expanded = false
        }
    }

    // Dock entries: the music button opens the MPRIS Spotify popup, the
    // pencil the Excalidraw whiteboard, the book the bookshelf picker. All
    // are 36x36 rounded buttons in the dock pill style; an open popup
    // highlights its button.
    component DockButton: Rectangle {
        id: dockBtn
        required property string glyph
        required property color glyphColor
        required property bool active
        required property bool highlighted
        width: 36
        height: 36
        radius: 10
        color: mouse.containsMouse || dockBtn.active ? sidebar.shell.dimColor : Qt.rgba(1, 1, 1, 0.04)
        border.width: dockBtn.highlighted ? 1 : 0
        border.color: sidebar.shell.accentColor
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: dockBtn.glyph
            font.family: sidebar.shell.iconFont
            font.pointSize: 13
            color: dockBtn.glyphColor
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dockBtn.clicked()
        }
        signal clicked()
    }

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
            // Tucked away: fully outside the surface (invisible), not a
            // visible sliver. Slides in from the edge when shown.
            x: sidebar.shown ? sidebar.shell.sidebarGap : -width - 8
            width: sidebar.shell.sidebarWidth
            height: Math.min(dockCol.implicitHeight + 16, parent.height - 2 * sidebar.shell.sidebarVMargin)
            y: (parent.height - height) / 2
            radius: width / 2
            color: sidebar.shell.barColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            opacity: sidebar.shown ? 1 : 0
            clip: true
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Column {
                id: dockCol
                anchors.centerIn: parent
                spacing: 6

                DockButton {
                    glyph: "\uf1bc"
                    glyphColor: "#1db954"
                    active: sidebar.spotifyOpen
                    highlighted: sidebar.spotifyOpen
                    onClicked: shell.spotifyPopup.toggle()
                }

                DockButton {
                    glyph: "\uf040"
                    glyphColor: sidebar.shell.exAccentColor
                    active: sidebar.exOpen
                    highlighted: sidebar.exOpen
                    onClicked: shell.excalidrawPopup.toggle()
                }

                Rectangle {
                    width: 22
                    height: 1
                    radius: 0.5
                    color: sidebar.shell.dimColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Opens the book picker popup.
                DockButton {
                    glyph: "\uf02d"
                    glyphColor: sidebar.shell.accentColor
                    active: sidebar.pickerOpen
                    highlighted: sidebar.pickerOpen
                    onClicked: shell.bookPopup.toggle()
                }
            }
        }
    }
}
