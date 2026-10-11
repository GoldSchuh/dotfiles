import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: notes

    required property var shell
    property bool open: false
    property var noteList: []
    property string view: "list"
    property string editingId: ""
    property string confirmDeleteId: ""
    property int selectedIndex: 0
    property bool kbdCursor: false
    property int editFocusIndex: 0
    property bool fieldActive: false
    property bool suppressSave: false
    property int popupWidth: 500
    property var popup: notesPopup

    readonly property int maxNotes: 500
    readonly property int maxTitleLength: 200
    readonly property int maxBodyLength: 20000
    readonly property int maxFileBytes: 12 * 1024 * 1024

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/quickshell/quick-notes"
    readonly property string notesPath: stateDir + "/notes.json"

    readonly property var sortedNotes: {
        var arr = noteList.slice()
        arr.sort(function (a, b) { return (b.updatedAt || 0) - (a.updatedAt || 0) })
        return arr
    }

    readonly property bool cursorOnPlus: view === "list" && kbdCursor && !fieldActive && selectedIndex === 0
    readonly property bool editCursorOnBack: view === "edit" && kbdCursor && !fieldActive && editFocusIndex === 0
    readonly property bool editCursorOnTitle: view === "edit" && kbdCursor && !fieldActive && editFocusIndex === 1
    readonly property bool editCursorOnBody: view === "edit" && kbdCursor && !fieldActive && editFocusIndex === 2
    readonly property bool editCursorOnDelete: view === "edit" && kbdCursor && !fieldActive && editFocusIndex === 3

    implicitWidth: notesButton.implicitWidth
    implicitHeight: shell.barHeight

    function makeId() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
    }

    function findNote(id) {
        for (var i = 0; i < noteList.length; i++)
            if (noteList[i].id === id) return noteList[i]
        return null
    }

    function noteTitleFor(note) {
        var t = String((note && note.title) || "").trim()
        return t !== "" ? t : "Untitled"
    }

    function notePreviewFor(note) {
        var b = String((note && note.body) || "").replace(/\s+/g, " ").trim()
        return b.length > 72 ? b.slice(0, 72) + "…" : b
    }

    function sanitizeNote(raw) {
        if (!raw || typeof raw !== "object") return null
        var id = typeof raw.id === "string" && raw.id !== "" ? raw.id : makeId()
        var title = typeof raw.title === "string" ? raw.title.slice(0, maxTitleLength) : ""
        var body = typeof raw.body === "string" ? raw.body.slice(0, maxBodyLength) : ""
        var updatedAt = Number(raw.updatedAt)
        if (!isFinite(updatedAt)) updatedAt = 0
        return { id: id, title: title, body: body, updatedAt: updatedAt }
    }

    function loadNotesText(text) {
        if (typeof text !== "string" || text.length > maxFileBytes) {
            noteList = []
            return
        }
        var parsed
        try {
            parsed = JSON.parse(text)
        } catch (e) {
            noteList = []
            return
        }
        if (!Array.isArray(parsed)) { noteList = []; return }

        var seenIds = ({})
        var cleaned = []
        for (var i = 0; i < parsed.length; i++) {
            var n = sanitizeNote(parsed[i])
            if (!n) continue
            if (seenIds[n.id]) n.id = makeId()
            seenIds[n.id] = true
            cleaned.push(n)
        }
        cleaned.sort(function (a, b) { return (b.updatedAt || 0) - (a.updatedAt || 0) })
        if (cleaned.length > maxNotes) cleaned = cleaned.slice(0, maxNotes)
        noteList = cleaned
    }

    function statCheck(reason) {
        if (statProc.running) return
        statProc.pendingReason = reason
        statProc.running = true
    }

    function handleStatResult(output, reason) {
        var size = parseInt(String(output).trim(), 10)
        if (!isFinite(size)) {
            if (reason === "initial") noteList = []
            return
        }
        if (size > maxFileBytes) {
            console.warn("Quick Notes: notes.json is " + size + " bytes, exceeds the " + maxFileBytes + " byte limit; refusing to load it.")
            if (reason === "initial") noteList = []
            return
        }
        notesFile.reload()
    }

    function persist() {
        var payload = JSON.stringify(noteList, null, 2)
        if (payload.length > maxFileBytes) {
            console.warn("Quick Notes: refusing to write notes.json - serialized size exceeds the " + maxFileBytes + " byte limit")
            return
        }
        Quickshell.execDetached(["mkdir", "-p", stateDir])
        notesFile.setText(payload)
    }

    function removeNoteInternal(id) {
        noteList = noteList.filter(function (n) { return n.id !== id })
    }

    function createNote() {
        if (confirmDeleteId !== "" || noteList.length >= maxNotes) return
        var note = { id: makeId(), title: "", body: "", updatedAt: Date.now() }
        noteList = noteList.concat([note])
        openNote(note.id)
    }

    function openNote(id) {
        confirmDeleteId = ""
        var n = findNote(id)
        suppressSave = true
        editingId = id
        titleEdit.text = n ? n.title : ""
        bodyEdit.text = n ? n.body : ""
        suppressSave = false
        view = "edit"
        kbdCursor = true
        fieldActive = true
        editFocusIndex = 1
        Qt.callLater(function () { titleEdit.forceActiveFocus(Qt.PopupFocusReason) })
    }

    function scheduleSave() {
        saveDebounce.restart()
    }

    function saveNow() {
        saveDebounce.stop()
        commitEdit()
    }

    function newNoteFromEditor() {
        goBack()
        createNote()
    }

    function leaveField(focusIndex) {
        fieldActive = false
        kbdCursor = true
        editFocusIndex = focusIndex
        Qt.callLater(function () { keyCatcher.forceActiveFocus(Qt.PopupFocusReason) })
    }

    function fieldFocusChanged() {
        if (titleEdit.activeFocus) { fieldActive = true; kbdCursor = true; editFocusIndex = 1; return }
        if (bodyEdit.activeFocus) { fieldActive = true; kbdCursor = true; editFocusIndex = 2; return }
        Qt.callLater(function () {
            if (titleEdit.activeFocus || bodyEdit.activeFocus) return
            fieldActive = false
            keyCatcher.forceActiveFocus(Qt.PopupFocusReason)
        })
    }

    function commitEdit() {
        if (editingId === "") return
        var id = editingId
        var title = titleEdit.text.slice(0, maxTitleLength)
        var body = bodyEdit.text.slice(0, maxBodyLength)
        noteList = noteList.map(function (n) {
            if (n.id !== id) return n
            return { id: n.id, title: title, body: body, updatedAt: Date.now() }
        })
        persist()
    }

    function goBack() {
        saveDebounce.stop()
        if (editingId !== "") commitEdit()
        var n = findNote(editingId)
        if (n && String(n.title).trim() === "" && String(n.body).trim() === "") {
            removeNoteInternal(editingId)
            persist()
        }
        editingId = ""
        view = "list"
        fieldActive = false
        editFocusIndex = 0
        Qt.callLater(function () { keyCatcher.forceActiveFocus(Qt.PopupFocusReason) })
    }

    function requestDelete(id) {
        confirmDeleteId = id
    }

    function cancelDeleteConfirm() {
        confirmDeleteId = ""
    }

    function performDelete() {
        var id = confirmDeleteId
        if (id === "") return
        confirmDeleteId = ""
        removeNoteInternal(id)
        persist()
        if (editingId === id) {
            editingId = ""
            view = "list"
            fieldActive = false
            editFocusIndex = 0
        }
        var count = sortedNotes.length
        if (selectedIndex > count) selectedIndex = count
    }

    function moveCursor(delta) {
        if (confirmDeleteId !== "") return
        var count = sortedNotes.length
        if (!kbdCursor) {
            kbdCursor = true
            if (selectedIndex < 0 || selectedIndex > count) selectedIndex = count > 0 ? 1 : 0
            return
        }
        selectedIndex = Math.max(0, Math.min(count, selectedIndex + delta))
    }

    function moveEditCursor(delta) {
        if (confirmDeleteId !== "") return
        if (!kbdCursor) { kbdCursor = true; return }
        editFocusIndex = Math.max(0, Math.min(3, editFocusIndex + delta))
    }

    function handleActivate() {
        if (confirmDeleteId !== "" || !kbdCursor) return
        if (selectedIndex === 0) { createNote(); return }
        var list = sortedNotes
        var i = selectedIndex - 1
        if (i >= 0 && i < list.length) openNote(list[i].id)
    }

    function handleDeleteKey() {
        if (confirmDeleteId !== "" || !kbdCursor || selectedIndex === 0) return
        var list = sortedNotes
        var i = selectedIndex - 1
        if (i >= 0 && i < list.length) requestDelete(list[i].id)
    }

    function handleEditActivate() {
        if (confirmDeleteId !== "" || !kbdCursor) return
        if (editFocusIndex === 0) { goBack(); return }
        if (editFocusIndex === 1) { titleEdit.forceActiveFocus(Qt.PopupFocusReason); return }
        if (editFocusIndex === 2) { bodyEdit.forceActiveFocus(Qt.PopupFocusReason); return }
        if (editFocusIndex === 3 && editingId !== "") { requestDelete(editingId); return }
    }

    function handlePanelClose() {
        if (confirmDeleteId !== "") { cancelDeleteConfirm(); return }
        if (view === "edit") { goBack(); return }
        close()
    }

    function toggle() {
        open = !open
        shell.ccPopup.visible = false
        shell.bookPopup.visible = false
        shell.spotifyPopup.visible = false
        shell.excalidrawPopup.visible = false
        notesPopup.visible = open
    }

    function close() {
        saveDebounce.stop()
        if (editingId !== "") goBack()
        confirmDeleteId = ""
        fieldActive = false
        open = false
        notesPopup.visible = false
    }

    Component.onCompleted: statCheck("initial")

    Timer {
        id: saveDebounce
        interval: 400
        onTriggered: notes.commitEdit()
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: {
            if (!notes.open) { stop(); return }
            var fieldHasFocus = notes.fieldActive && (titleEdit.activeFocus || bodyEdit.activeFocus)
            var keyHasFocus = !notes.fieldActive && keyCatcher.activeFocus
            if (fieldHasFocus || keyHasFocus) return
            if (notesPopup._backingWindow)
                notesPopup._backingWindow.requestActivate()
            if (notes.fieldActive)
                (notes.editFocusIndex === 2 ? bodyEdit : titleEdit).forceActiveFocus(Qt.PopupFocusReason)
            else
                keyCatcher.forceActiveFocus(Qt.PopupFocusReason)
        }
    }

    FileView {
        id: notesFile
        path: notes.notesPath
        preload: false
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: notes.loadNotesText(notesFile.text())
        onLoadFailed: notes.loadNotesText("[]")
        onFileChanged: notes.statCheck("changed")
    }

    Process {
        id: statProc
        property string pendingReason: ""
        command: ["stat", "-c", "%s", notes.notesPath]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: notes.handleStatResult(text, statProc.pendingReason)
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

    component IconButton: Rectangle {
        id: ib
        property string icon
        property bool cursorOn: false
        property bool danger: false
        property bool hovered: mo.containsMouse
        signal activated()
        width: 26
        height: 26
        radius: 8
        color: cursorOn || hovered ? Qt.lighter(notes.shell.ccBgColor, 1.45) : "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        Text {
            anchors.centerIn: parent
            text: ib.icon
            font.family: notes.shell.iconFont
            font.pointSize: 10
            color: ib.danger ? notes.shell.dangerColor : notes.shell.textColor
        }
        MouseArea {
            id: mo
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.activated()
        }
    }

    PanelWindow {
        id: notesPopup
        anchors { top: true; left: true; right: true }
        implicitHeight: notesBody.height + notes.shell.windowGap - 3
        exclusiveZone: 0
        visible: false
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-quick-notes"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            notes.open = visible
            if (visible) {
                notes.view = "list"
                notes.editingId = ""
                notes.confirmDeleteId = ""
                notes.kbdCursor = false
                notes.fieldActive = false
                notes.editFocusIndex = 0
                notes.selectedIndex = notes.sortedNotes.length > 0 ? 1 : 0
                focusTimer.start()
            } else {
                focusTimer.stop()
                saveDebounce.stop()
                if (notes.editingId !== "") notes.commitEdit()
            }
        }

        Shortcut {
            sequence: "Ctrl+S"
            enabled: notesPopup.visible && notes.view === "edit"
            onActivated: notes.saveNow()
        }

        Shortcut {
            sequence: "Ctrl+N"
            enabled: notesPopup.visible
            onActivated: {
                if (notes.view === "edit") notes.newNoteFromEditor()
                else notes.createNote()
            }
        }

        Shortcut {
            sequence: "Ctrl+Backspace"
            enabled: notesPopup.visible && notes.view === "edit" && notes.editingId !== ""
            onActivated: notes.requestDelete(notes.editingId)
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

                Item {
                    id: keyCatcher
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    focus: false

                    Keys.onPressed: function (event) {
                        var key = event.key
                        if (key === Qt.Key_Escape) {
                            notes.handlePanelClose()
                            event.accepted = true
                            return
                        }
                        if (notes.confirmDeleteId !== "") { event.accepted = true; return }
                        if (notes.view === "list") {
                            if (key === Qt.Key_Up || key === Qt.Key_Left || key === Qt.Key_K) {
                                notes.moveCursor(-1)
                                event.accepted = true
                            } else if (key === Qt.Key_Down || key === Qt.Key_Right || key === Qt.Key_J) {
                                notes.moveCursor(1)
                                event.accepted = true
                            } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
                                notes.handleActivate()
                                event.accepted = true
                            } else if (key === Qt.Key_N) {
                                notes.createNote()
                                event.accepted = true
                            } else if (key === Qt.Key_X) {
                                notes.handleDeleteKey()
                                event.accepted = true
                            }
                        } else {
                            if (key === Qt.Key_Up || key === Qt.Key_Left || key === Qt.Key_H) {
                                notes.moveEditCursor(-1)
                                event.accepted = true
                            } else if (key === Qt.Key_Down || key === Qt.Key_Right || key === Qt.Key_L) {
                                notes.moveEditCursor(1)
                                event.accepted = true
                            } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
                                notes.handleEditActivate()
                                event.accepted = true
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: notes.view === "list"
                    Layout.fillWidth: true
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Math.max(headerLabel.implicitHeight, 26)

                        Text {
                            id: headerLabel
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf249 Notes"
                            font.family: notes.shell.iconFont
                            font.pointSize: 9
                            font.bold: true
                            color: notes.shell.accentColor
                        }

                        IconButton {
                            id: addButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "\uf067"
                            cursorOn: notes.cursorOnPlus
                            enabled: notes.noteList.length < notes.maxNotes
                            onActivated: notes.createNote()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                    ListView {
                        id: notesListView
                        Layout.fillWidth: true
                        height: Math.min(contentHeight, 280)
                        visible: notes.sortedNotes.length > 0
                        clip: true
                        spacing: 8
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height
                        model: notes.sortedNotes
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                implicitWidth: 3
                                radius: 1.5
                                color: Qt.rgba(1, 1, 1, 0.25)
                            }
                        }

                        delegate: Item {
                            id: noteRow
                            required property var modelData
                            required property int index

                            width: notesListView.width
                            implicitHeight: rowContent.implicitHeight + 16

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: (notes.kbdCursor && !notes.fieldActive && notes.selectedIndex === noteRow.index + 1) || rowMouse.containsMouse
                                       ? Qt.rgba(0, 0, 0, 0.22) : "transparent"
                            }

                            Column {
                                id: rowContent
                                anchors {
                                    left: parent.left
                                    right: rowDelete.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 10
                                    rightMargin: 8
                                }
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: notes.noteTitleFor(noteRow.modelData)
                                    textFormat: Text.PlainText
                                    color: notes.shell.textColor
                                    font.pointSize: 10
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: notes.notePreviewFor(noteRow.modelData)
                                    textFormat: Text.PlainText
                                    visible: text !== ""
                                    color: Qt.rgba(1, 1, 1, 0.55)
                                    font.pointSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            IconButton {
                                id: rowDelete
                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                icon: "\uf1f8"
                                danger: true
                                onActivated: notes.requestDelete(noteRow.modelData.id)
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: { notes.kbdCursor = true; notes.selectedIndex = noteRow.index + 1 }
                                onClicked: notes.openNote(noteRow.modelData.id)
                            }
                        }
                    }

                    Text {
                        visible: notes.sortedNotes.length === 0
                        text: "No notes yet. Press + to create one."
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.pointSize: 9
                        wrapMode: Text.WordWrap
                    }
                }

                ColumnLayout {
                    visible: notes.view === "edit"
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        IconButton {
                            icon: "\uf060"
                            cursorOn: notes.editCursorOnBack
                            onActivated: notes.goBack()
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            visible: notes.editingId !== ""
                            text: "Ctrl+S to save · autosaves"
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.pointSize: 8
                        }

                        IconButton {
                            icon: "\uf1f8"
                            danger: true
                            cursorOn: notes.editCursorOnDelete
                            enabled: notes.editingId !== ""
                            onActivated: {
                                if (notes.editingId !== "") notes.requestDelete(notes.editingId)
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.2)
                        border.width: 1
                        border.color: notes.editCursorOnTitle ? notes.shell.accentColor : Qt.rgba(1, 1, 1, 0.04)

                        Text {
                            anchors { left: parent.left; leftMargin: 10 }
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Title"
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font.pointSize: 10
                            visible: titleEdit.text.length === 0 && !titleEdit.activeFocus
                        }

                        TextEdit {
                            id: titleEdit
                            anchors.fill: parent
                            color: notes.shell.textColor
                            font.pointSize: 10
                            font.bold: true
                            selectionColor: notes.shell.accentColor
                            selectedTextColor: "#2a1010"
                            activeFocusOnPress: true
                            leftPadding: 10
                            rightPadding: 10
                            verticalAlignment: TextEdit.AlignVCenter
                            wrapMode: TextEdit.NoWrap
                            onTextChanged: {
                                if (text.length > notes.maxTitleLength) {
                                    var pos = cursorPosition
                                    text = text.slice(0, notes.maxTitleLength)
                                    cursorPosition = Math.min(pos, text.length)
                                    return
                                }
                                if (!notes.suppressSave) notes.scheduleSave()
                            }
                            onActiveFocusChanged: notes.fieldFocusChanged()
                            Keys.onReturnPressed: event.accepted = true
                            Keys.onEnterPressed: event.accepted = true
                            Keys.onEscapePressed: {
                                notes.leaveField(1)
                                event.accepted = true
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 240
                        radius: 10
                        color: notes.editCursorOnBody ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.2)
                        border.width: 1
                        border.color: notes.editCursorOnBody ? notes.shell.accentColor : Qt.rgba(1, 1, 1, 0.04)

                        Text {
                            anchors { left: parent.left; top: parent.top; leftMargin: 10; topMargin: 8 }
                            text: "Write a note..."
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font.pointSize: 10
                            visible: bodyEdit.text.length === 0 && !bodyEdit.activeFocus
                        }

                        TextEdit {
                            id: bodyEdit
                            anchors.fill: parent
                            clip: true
                            color: notes.shell.textColor
                            selectionColor: notes.shell.accentColor
                            selectedTextColor: "#2a1010"
                            wrapMode: TextEdit.Wrap
                            activeFocusOnPress: true
                            font.pointSize: 10
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 8
                            bottomPadding: 8
                            onTextChanged: {
                                if (text.length > notes.maxBodyLength) {
                                    var pos = cursorPosition
                                    text = text.slice(0, notes.maxBodyLength)
                                    cursorPosition = Math.min(pos, text.length)
                                    return
                                }
                                if (!notes.suppressSave) notes.scheduleSave()
                            }
                            onActiveFocusChanged: notes.fieldFocusChanged()
                            Keys.onEscapePressed: {
                                notes.leaveField(2)
                                event.accepted = true
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: notes.confirmDeleteId !== ""
                anchors.fill: parent
                radius: notes.shell.cornerRadius
                color: Qt.rgba(0, 0, 0, 0.55)
                z: 50

                Text {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14 }
                    text: "Delete this note? This can't be undone."
                    color: notes.shell.textColor
                    font.pointSize: 10
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 10 }
                    spacing: 8

                    Rectangle {
                        width: 62; height: 26; radius: 8
                        color: confCancel.containsMouse ? Qt.lighter(notes.shell.ccBgColor, 1.45) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: notes.shell.textColor
                            font.pointSize: 9
                        }
                        MouseArea {
                            id: confCancel
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notes.cancelDeleteConfirm()
                        }
                    }

                    Rectangle {
                        width: 62; height: 26; radius: 8
                        color: notes.shell.dangerColor
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            color: "#f2ece0"
                            font.pointSize: 9
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notes.performDelete()
                        }
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
}
