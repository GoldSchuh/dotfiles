import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

Item {
    id: control
    required property var shell
    property bool open: false
    property var popup: ccPopup

    implicitWidth: 26
    implicitHeight: shell.barHeight

    readonly property var players: Mpris.players.values
    property var player: {
        if (players) {
            for (let i = 0; i < players.length; ++i)
                if (players[i].isPlaying) return players[i]
            if (players.length > 0) return players[0]
        }
        return null
    }
    readonly property var sink: Pipewire.defaultAudioSink

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    component CcButton: Button {
        id: btn
        font.pointSize: 11
        contentItem: Text {
            text: btn.text
            font: btn.font
            color: btn.enabled ? control.shell.textColor : Qt.rgba(1, 1, 1, 0.35)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            implicitWidth: 34
            implicitHeight: 34
            radius: height / 2
            color: !btn.enabled ? Qt.darker(control.shell.ccBgColor, 1.05)
                : btn.pressed ? Qt.darker(control.shell.ccBgColor, 1.3)
                : btn.hovered ? Qt.lighter(control.shell.ccBgColor, 1.45)
                : Qt.lighter(control.shell.ccBgColor, 1.25)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            opacity: btn.enabled ? 1 : 0.6
        }
    }

    Process {
        id: powerProc
        command: ["systemctl", "poweroff"]
    }

    Process {
        id: rebootProc
        command: ["systemctl", "reboot"]
    }

    Process {
        id: niriQuitProc
        command: ["niri", "msg", "action", "quit"]
    }

    Item {
        id: ccButton
        width: 26
        height: shell.barHeight

        Rectangle { anchors.fill: parent; radius: 8; color: control.open ? shell.dimColor : "transparent" }
        Text { anchors.centerIn: parent; text: "\uf1de"; font.family: shell.iconFont; font.pointSize: 10; color: shell.textColor }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: control.toggle()
        }
    }

    function toggle() {
        open = !open
        shell.notesPopup.visible = false
        shell.bookPopup.visible = false
        ccPopup.visible = open
    }

    PopupWindow {
        id: ccPopup
        implicitWidth: shell.ccWidth + 16
        implicitHeight: ccBody.height + 16
        visible: false
        color: "transparent"
        grabFocus: true
        anchor {
            item: ccButton
            edges: Edges.Bottom | Edges.Right
            gravity: Edges.Bottom | Edges.Left
            margins.top: 8
        }
        onVisibleChanged: control.open = visible

        Rectangle {
            id: ccBody
            x: 8
            y: 8
            width: parent.width - 16
            height: ccLayout.implicitHeight + 28
            radius: shell.cornerRadius
            color: shell.ccBgColor
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                id: ccLayout
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Text { text: "Now Playing"; font.pointSize: 9; font.bold: true; color: shell.accentColor }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 46; Layout.preferredHeight: 46; radius: 10
                        color: Qt.rgba(0, 0, 0, 0.25); clip: true
                        Text { anchors.centerIn: parent; text: "\uf001"; font.family: shell.iconFont; font.pointSize: 15; color: Qt.rgba(1, 1, 1, 0.3); visible: !art.visible }
                        Image { id: art; anchors.fill: parent; source: control.player ? control.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready || status === Image.Loading }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: control.player ? (control.player.trackTitle || "Unknown Title") : "Nothing Playing"; font.pointSize: 10; font.bold: true; color: shell.textColor; elide: Text.ElideRight; maximumLineCount: 1 }
                        Text { Layout.fillWidth: true; text: control.player ? (control.player.trackArtist || "Unknown Artist") : "No media is playing"; font.pointSize: 9; color: Qt.rgba(1, 1, 1, 0.6); elide: Text.ElideRight; maximumLineCount: 1 }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    CcButton { text: "\uf04a"; font.family: shell.iconFont; enabled: !!control.player && control.player.canGoPrevious; onClicked: control.player.previous() }
                    CcButton { text: control.player && control.player.isPlaying ? "\uf04c" : "\uf04b"; font.family: shell.iconFont; enabled: !!control.player && control.player.canTogglePlaying; onClicked: control.player.togglePlaying() }
                    CcButton { text: "\uf04e"; font.family: shell.iconFont; enabled: !!control.player && control.player.canGoNext; onClicked: control.player.next() }
                    Item { Layout.fillWidth: true }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                Text { text: "Lautstärke"; font.pointSize: 9; font.bold: true; color: shell.accentColor }
                RowLayout {
                    Layout.fillWidth: true
                    CcButton { text: control.sink && (control.sink.audio.muted || control.sink.audio.volume === 0) ? "\uf026" : "\uf028"; font.family: shell.iconFont; enabled: !!control.sink; onClicked: control.sink.audio.muted = !control.sink.audio.muted }
                    Slider {
                        id: volume
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        stepSize: 0.02
                        value: control.sink ? control.sink.audio.volume : 0
                        onMoved: if (control.sink) control.sink.audio.volume = value
                        background: Rectangle {
                            x: volume.leftPadding
                            y: volume.topPadding + volume.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 20
                            width: volume.availableWidth
                            height: 6
                            radius: 3
                            color: Qt.rgba(0, 0, 0, 0.25)
                            Rectangle {
                                width: volume.visualPosition * parent.width
                                height: parent.height
                                radius: 3
                                color: Qt.lighter(shell.ccBgColor, 1.5)
                            }
                        }
                        handle: Rectangle {
                            x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                            y: volume.topPadding + volume.availableHeight / 2 - height / 2
                            implicitWidth: 16
                            implicitHeight: 16
                            width: 16
                            height: 16
                            radius: 8
                            color: volume.pressed ? Qt.lighter(shell.ccBgColor, 1.8) : Qt.lighter(shell.ccBgColor, 1.45)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                        }
                    }
                    Text { text: control.sink ? Math.round(control.sink.audio.volume * 100) + "%" : "--%"; color: Qt.rgba(1, 1, 1, 0.6) }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    CcButton { text: "\uf011"; font.family: shell.iconFont; onClicked: powerProc.running = true }
                    CcButton { text: "\uf021"; font.family: shell.iconFont; onClicked: rebootProc.running = true }
                    CcButton { text: "\uf2f5"; font.family: shell.iconFont; onClicked: niriQuitProc.running = true }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        MultiEffect {
            source: ccBody
            anchors.fill: ccBody
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.35
            shadowBlur: 0.6
            shadowVerticalOffset: 4
            z: -1
        }
    }
}
