import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland

// Spotify popup for the sidebar dock, driven entirely by MPRIS. Spotify the
// Electron app stays a normal Wayland window; this panel controls it from
// outside, so it only exists while it is toggled open (dock button / IPC).
//
// Playback controls (play/pause, next/previous, seek, volume) plus shuffle
// and loop, which Spotify's MPRIS implementation actually supports. A true
// playlist switcher is NOT possible here: the MPRIS spec has a Playlists
// interface, but neither Quickshell's Mpris module nor Spotify exposes it —
// the closest hack would be OpenUri, which just opens the playlist inside
// the main Spotify window.
//
// Player selection prefers a player whose identity contains "spotify", and
// falls back to any MPRIS player (e.g. Firefox) so the panel still works
// when something else is playing. While Spotify is not running at all, an
// empty state offers to launch it.
//
// The MPRIS position property is not reactive on its own (reading it always
// works, but property updates are suppressed to save CPU). The documented
// pattern is a Timer that manually emits player.positionChanged() while
// playing; position and length are plain seconds with ms precision. Seeking
// writes through to the player via setPosition() (guarded by canSeek).
PanelWindow {
    id: spotifyWin

    required property var shell

    property bool open: false
    property var popup: spotifyWin

    readonly property var players: Mpris.players.values
    property var player: {
        if (players) {
            for (let i = 0; i < players.length; ++i)
                if ((players[i].identity || "").toLowerCase().indexOf("spotify") !== -1)
                    return players[i]
            if (players.length > 0) return players[0]
        }
        return null
    }

    anchors { left: true; top: true }
    implicitWidth: 340
    implicitHeight: body.height + 16
    margins {
        left: shell.sidebarGap + shell.sidebarWidth + 8
        top: Math.max(8, (screen.height - implicitHeight) / 2)
    }
    exclusiveZone: 0
    visible: false
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-spotify"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: open = visible

    Timer {
        interval: 500
        running: spotifyWin.visible && spotifyWin.player && spotifyWin.player.isPlaying
        repeat: true
        // Position is deliberately non-reactive upstream; this manual signal
        // emission is the documented way to make `position` bindings tick.
        onTriggered: if (spotifyWin.player) spotifyWin.player.positionChanged()
    }

    function fmt(sec) {
        if (!sec || sec <= 0) return "0:00"
        var s = Math.floor(sec)
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    function toggle() {
        if (shell.ccPopup) shell.ccPopup.visible = false
        if (shell.notesPopup) shell.notesPopup.visible = false
        if (shell.bookPopup) shell.bookPopup.visible = false
        open = !open
        visible = open
    }

    function close() {
        open = false
        visible = false
    }

    Shortcut {
        sequence: "Escape"
        enabled: spotifyWin.visible
        onActivated: spotifyWin.close()
    }

    component CtrlButton: Button {
        id: btn
        property bool active: false
        font.pointSize: 11
        contentItem: Text {
            text: btn.text
            font: btn.font
            color: btn.active ? spotifyWin.shell.accentColor
                : btn.enabled ? spotifyWin.shell.textColor : Qt.rgba(1, 1, 1, 0.35)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            implicitWidth: 40
            implicitHeight: 40
            radius: height / 2
            color: !btn.enabled ? Qt.darker(spotifyWin.shell.ccBgColor, 1.05)
                : btn.pressed ? Qt.darker(spotifyWin.shell.ccBgColor, 1.3)
                : btn.hovered ? Qt.lighter(spotifyWin.shell.ccBgColor, 1.45)
                : Qt.lighter(spotifyWin.shell.ccBgColor, 1.25)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            opacity: btn.enabled ? 1 : 0.6
        }
    }

    component SpSlider: Slider {
        id: slider
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 200
            implicitHeight: 20
            width: slider.availableWidth
            height: 6
            radius: 3
            color: Qt.rgba(0, 0, 0, 0.25)
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: 3
                color: spotifyWin.shell.accentColor
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            implicitWidth: 14
            implicitHeight: 14
            width: 14
            height: 14
            radius: 7
            color: slider.pressed ? Qt.lighter(spotifyWin.shell.ccBgColor, 1.8) : spotifyWin.shell.accentColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.15)
        }
    }

    Item {
        anchors.fill: parent

        MultiEffect {
            source: body
            anchors.fill: body
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.35
            shadowBlur: 0.6
            shadowVerticalOffset: 4
            z: -1
        }

        Rectangle {
            id: body
            x: 8
            y: 8
            width: parent.width - 16
            height: spotifyCol.implicitHeight + 28
            radius: shell.cornerRadius
            color: shell.ccBgColor
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                id: spotifyCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // Empty state: no MPRIS player running.
                ColumnLayout {
                    visible: !spotifyWin.player
                    spacing: 10

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "\uf1bc"
                        font.family: shell.iconFont
                        font.pointSize: 28
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Spotify is not running"
                        font.pointSize: 10
                        font.bold: true
                        color: shell.textColor
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No MPRIS player found"
                        font.pointSize: 9
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                    CtrlButton {
                        Layout.alignment: Qt.AlignHCenter
                        text: "\uf04b"
                        font.family: shell.iconFont
                        onClicked: Quickshell.execDetached(["spotify"])
                    }
                }

                // Player content.
                Rectangle {
                    visible: !!spotifyWin.player
                    Layout.fillWidth: true
                    Layout.preferredHeight: 288
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.25)
                    clip: true
                    Text {
                        anchors.centerIn: parent
                        text: "\uf001"
                        font.family: shell.iconFont
                        font.pointSize: 32
                        color: Qt.rgba(1, 1, 1, 0.3)
                        visible: art.status !== Image.Ready && art.status !== Image.Loading
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: spotifyWin.player ? spotifyWin.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }
                Text {
                    visible: !!spotifyWin.player
                    Layout.fillWidth: true
                    text: spotifyWin.player ? (spotifyWin.player.trackTitle || "Unknown Title") : ""
                    font.pointSize: 11
                    font.bold: true
                    color: shell.textColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Text {
                    visible: !!spotifyWin.player
                    Layout.fillWidth: true
                    text: spotifyWin.player ? (spotifyWin.player.trackArtist || "Unknown Artist") : ""
                    font.pointSize: 9
                    color: Qt.rgba(1, 1, 1, 0.6)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                RowLayout {
                    visible: !!spotifyWin.player
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: spotifyWin.fmt(spotifyWin.player ? spotifyWin.player.position : 0)
                        font.pointSize: 8
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                    SpSlider {
                        id: seek
                        Layout.fillWidth: true
                        from: 0
                        to: spotifyWin.player ? Math.max(spotifyWin.player.length, 1) : 1
                        value: seek.pressed ? seek.scrubPos : (spotifyWin.player ? spotifyWin.player.position : 0)
                        enabled: !!spotifyWin.player && spotifyWin.player.canSeek
                        onPressedChanged: {
                            if (pressed) {
                                seek.scrubPos = value
                            } else if (spotifyWin.player && spotifyWin.player.canSeek) {
                                spotifyWin.player.setPosition(value)
                            }
                        }
                        onMoved: if (pressed) seek.scrubPos = value
                        property real scrubPos: 0
                    }
                    Text {
                        text: spotifyWin.fmt(spotifyWin.player ? spotifyWin.player.length : 0)
                        font.pointSize: 8
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                }
                RowLayout {
                    visible: !!spotifyWin.player
                    Layout.fillWidth: true
                    spacing: 8
                    CtrlButton {
                        text: "\uf074"
                        font.family: shell.iconFont
                        font.pointSize: 10
                        enabled: !!spotifyWin.player && spotifyWin.player.canControl
                        active: !!spotifyWin.player && spotifyWin.player.shuffle
                        onClicked: if (spotifyWin.player) spotifyWin.player.shuffle = !spotifyWin.player.shuffle
                    }
                    CtrlButton {
                        text: "\uf04a"
                        font.family: shell.iconFont
                        enabled: !!spotifyWin.player && spotifyWin.player.canGoPrevious
                        onClicked: spotifyWin.player.previous()
                    }
                    CtrlButton {
                        text: spotifyWin.player && spotifyWin.player.isPlaying ? "\uf04c" : "\uf04b"
                        font.family: shell.iconFont
                        font.pointSize: 13
                        enabled: !!spotifyWin.player && spotifyWin.player.canTogglePlaying
                        onClicked: spotifyWin.player.togglePlaying()
                    }
                    CtrlButton {
                        text: "\uf04e"
                        font.family: shell.iconFont
                        enabled: !!spotifyWin.player && spotifyWin.player.canGoNext
                        onClicked: spotifyWin.player.next()
                    }
                    CtrlButton {
                        text: "\uf079"
                        font.family: shell.iconFont
                        font.pointSize: 10
                        enabled: !!spotifyWin.player && spotifyWin.player.canControl
                        active: !!spotifyWin.player && spotifyWin.player.loopStatus !== "None"
                        onClicked: if (spotifyWin.player) {
                            switch (spotifyWin.player.loopStatus) {
                            case "None": spotifyWin.player.loopStatus = "Track"; break
                            case "Track": spotifyWin.player.loopStatus = "Playlist"; break
                            default: spotifyWin.player.loopStatus = "None"
                            }
                        }
                    }
                }
                RowLayout {
                    visible: !!spotifyWin.player
                    Layout.fillWidth: true
                    spacing: 8
                    CtrlButton {
                        text: "\uf028"
                        font.family: shell.iconFont
                        font.pointSize: 10
                        enabled: !!spotifyWin.player
                        onClicked: spotifyWin.player.volume = 0
                    }
                    SpSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        stepSize: 0.01
                        value: spotifyWin.player ? spotifyWin.player.volume : 0
                        enabled: !!spotifyWin.player
                        onMoved: if (spotifyWin.player) spotifyWin.player.volume = value
                    }
                    Text {
                        text: spotifyWin.player ? Math.round(spotifyWin.player.volume * 100) + "%" : "--%"
                        font.pointSize: 8
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                }
            }
        }
    }
}
