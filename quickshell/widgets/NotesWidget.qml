import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: notes

    required property var shell
    property bool open: false
    property string noteText: ""
    property string noteDate: Qt.formatDate(new Date(), "dd-MM-yyyy")
    property int popupWidth: 500
    property var popup: notesPopup

    implicitWidth: notesButton.implicitWidth
    implicitHeight: shell.barHeight

    FileView {
        id: notesFile
        path: Quickshell.env("HOME") + "/Dokumente/Notizen/Tag/" + notes.noteDate + ".md"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: createFile
        command: ["sh", "-c", "mkdir -p ~/Dokumente/Notizen/Tag && touch ~/Dokumente/Notizen/Tag/" + notes.noteDate + ".md"]
        running: true
    }

    function loadNote() {
        var content = notesFile.text()
        notes.noteText = content
        notesEdit.text = content
    }

    Timer {
        id: dayTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            var today = Qt.formatDate(new Date(), "dd-MM-yyyy")
            if (today === notes.noteDate) return
            notesFile.setText(notes.noteText)
            notes.noteDate = today
            createFile.running = true
            notes.loadNote()
        }
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: notesFile.setText(notes.noteText)
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (!notes.open || notesEdit.activeFocus) {
                stop()
                return
            }
            if (notesPopup._backingWindow)
                notesPopup._backingWindow.requestActivate()
            notesEdit.forceActiveFocus(Qt.PopupFocusReason)
            notesEdit.cursorPosition = notesEdit.length
        }
    }

    Item {
        id: notesButton
        width: notesRow.implicitWidth + 16
        height: shell.barHeight

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: notes.open ? shell.dimColor : "transparent"
        }

        RowLayout {
            id: notesRow
            anchors.centerIn: parent
            spacing: 7

            Text {
                text: "\uf249"
                font.family: shell.iconFont
                font.pointSize: 10
                color: shell.textColor
            }
            Text {
                text: "Notes"
                color: Qt.rgba(1, 1, 1, 0.75)
                font.pointSize: 9
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: notes.toggle()
        }
    }

    function toggle() {
        open = !open
        shell.ccPopup.visible = false
        shell.bookPopup.visible = false
        shell.spotifyPopup.visible = false
        notesPopup.visible = open
    }

    PanelWindow {
        id: notesPopup
        anchors { top: true; left: true; right: true }
        implicitHeight: notesBody.height + notes.shell.windowGap - 3
        exclusiveZone: 0
        visible: false
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-notes-editor"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            notes.open = visible
            if (visible) {
                notes.loadNote()
                focusTimer.start()
            } else {
                focusTimer.stop()
                notesFile.setText(notes.noteText)
            }
        }

        // Handle dismissal at the window level as well as in the editor.
        Shortcut {
            sequence: "Escape"
            enabled: notesPopup.visible
            onActivated: notes.close()
        }

        Rectangle {
            id: notesBody
            x: (parent.width - notes.popupWidth) / 2
            y: notes.shell.windowGap - 3
            width: notes.popupWidth
            height: notesLayout.implicitHeight + 28
            radius: notes.shell.cornerRadius
            color: notes.shell.ccBgColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.04)

            ColumnLayout {
                id: notesLayout
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "\uf08d"; font.family: notes.shell.iconFont; font.pointSize: 10; color: notes.shell.accentColor }
                    Text { text: "Notes"; font.pointSize: 9; font.bold: true; color: notes.shell.accentColor }
                    Item { Layout.fillWidth: true }
                    Text { text: "autosaves"; font.pointSize: 8; color: Qt.rgba(1, 1, 1, 0.4) }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 440
                    color: Qt.rgba(0, 0, 0, 0.2)
                    radius: 10
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.04)

                    Text {
                        anchors { left: parent.left; top: parent.top; leftMargin: 10; topMargin: 8 }
                        text: "Write a note..."
                        color: Qt.rgba(1, 1, 1, 0.35)
                        font.pointSize: 10
                        visible: notesEdit.text.length === 0 && !notesEdit.activeFocus
                    }

                    TextEdit {
                        id: notesEdit
                        anchors.fill: parent
                        color: notes.shell.textColor
                        selectionColor: notes.shell.accentColor
                        selectedTextColor: "#2a1010"
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        focus: notesPopup.visible
                        activeFocusOnPress: true
                        font.pointSize: 10
                        leftPadding: 10
                        rightPadding: 10
                        topPadding: 8
                        bottomPadding: 8
                        Keys.onEscapePressed: {
                            event.accepted = true
                            notes.close()
                        }
                        onTextChanged: {
                            notes.noteText = text
                            saveTimer.restart()
                        }
                        Component.onCompleted: notes.loadNote()
                    }
                }
            }
        }

        MultiEffect {
            source: notesBody
            anchors.fill: notesBody
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.35
            shadowBlur: 0.6
            shadowVerticalOffset: 4
            z: -1
        }
    }

    function close() {
        saveTimer.stop()
        notesFile.setText(notes.noteText)
        open = false
        notesPopup.visible = false
    }
}
