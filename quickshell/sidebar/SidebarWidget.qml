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
    // expanded is sticky: entering sets it instantly, leaving starts a short
    // debounce (hideTimer) before collapsing. Resizing a layer surface can
    // transiently drop containsMouse — collapsing immediately on that made
    // the dock flicker between expanded and collapsed.
    property bool expanded: false
    readonly property bool shown: expanded || pickerOpen

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
            if (!hoverCatcher.containsMouse && !sidebar.pickerOpen)
                sidebar.expanded = false
        }
    }

    // Top-level inline component (nested declarations break signal lookup).
    component DockIcon: Rectangle {
        id: iconBtn
        required property var modelData
        width: 36
        height: 36
        radius: 10
        color: hoverArea.containsMouse ? sidebar.shell.dimColor : Qt.rgba(1, 1, 1, 0.04)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: iconBtn.modelData.glyph
            font.family: sidebar.shell.iconFont
            font.pointSize: 13
            color: iconBtn.modelData.color
        }
        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }
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

                Repeater {
                    model: sidebar.dockItems
                    delegate: DockIcon {}
                }

                Rectangle {
                    width: 22
                    height: 1
                    radius: 0.5
                    color: sidebar.shell.dimColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // The one real entry: opens the book picker popup.
                Rectangle {
                    id: bookButton
                    width: 36
                    height: 36
                    radius: 10
                    color: bookArea.containsMouse || sidebar.pickerOpen ? sidebar.shell.dimColor : Qt.rgba(1, 1, 1, 0.04)
                    border.width: sidebar.pickerOpen ? 1 : 0
                    border.color: sidebar.shell.accentColor
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf02d"
                        font.family: sidebar.shell.iconFont
                        font.pointSize: 13
                        color: sidebar.shell.accentColor
                    }
                    MouseArea {
                        id: bookArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shell.bookPopup.toggle()
                    }
                }
            }
        }
    }

    readonly property var dockItems: [
        { glyph: "\uf489", color: "#b9c2d8", name: "Terminal" },
        { glyph: "\uf121", color: "#21d789", name: "PyCharm" },
        { glyph: "\uf303", color: "#1793d1", name: "Arch Linux" },
        { glyph: "\uf11b", color: "#478cbf", name: "Godot" },
        { glyph: "\uf00a", color: "#1d99f3", name: "Apps" },
        { glyph: "\uf268", color: "#45b8ae", name: "Browser" },
        { glyph: "\uf269", color: "#ff9500", name: "Firefox" },
        { glyph: "\uf009", color: "#f59e0b", name: "Menu" }
    ]
}
