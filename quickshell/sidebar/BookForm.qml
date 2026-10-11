import QtQuick

// Reusable book form, a clone of bookshelfs' src/components/Form.vue:
// title, author, colour, pattern ID, height, cover picture and e-book file.
// The pick buttons only raise signals; the host (BookPicker) opens its own
// file browser, imports the picked file into the library and writes the
// stored library name back via setCover()/setFile() — the form never holds
// more than a transient source path before that.
Item {
    id: form

    required property var shell
    signal submitted()
    signal coverRequested()
    signal fileRequested()

    readonly property alias firstField: titleBox.field

    function values() {
        return {
            title: titleBox.text,
            author: authorBox.text,
            colour: colourBox.text,
            pattern: patternBox.text,
            height: heightBox.text,
            url: urlBox.text,
            file: fileBox.text
        }
    }

    function setFrom(book) {
        titleBox.text = book.title || ""
        authorBox.text = book.author || ""
        colourBox.text = (book.colour === undefined || book.colour === null) ? "" : String(book.colour)
        patternBox.text = (book.pattern === undefined || book.pattern === null) ? "" : String(book.pattern)
        heightBox.text = (book.height === undefined || book.height === null) ? "" : String(book.height)
        urlBox.text = (book.url === undefined || book.url === null || book.url === -1 || book.url === "-1") ? "" : String(book.url)
        fileBox.text = (book.file === undefined || book.file === null || book.file === -1 || book.file === "-1") ? "" : String(book.file)
    }

    function clear() {
        titleBox.text = ""
        authorBox.text = ""
        colourBox.text = ""
        patternBox.text = ""
        heightBox.text = ""
        urlBox.text = ""
        fileBox.text = ""
    }

    function setCover(p) {
        urlBox.text = p
    }

    function setFile(p) {
        fileBox.text = p
    }

    implicitHeight: fields.implicitHeight
    height: fields.implicitHeight

    component FieldBox: Rectangle {
        id: fieldBox
        property alias text: fieldInput.text
        property alias placeholder: fieldPlaceholder.text
        property alias validator: fieldInput.validator
        readonly property alias field: fieldInput
        width: parent.width
        height: 30
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.28)
        border.width: 1
        border.color: fieldInput.activeFocus ? form.shell.shelfAccentColor : "transparent"
        Behavior on border.color { ColorAnimation { duration: 120 } }

        TextInput {
            id: fieldInput
            anchors { fill: parent; margins: 7 }
            color: form.shell.shelfFgColor
            font.pointSize: 9
            selectByMouse: true
            clip: true
            activeFocusOnPress: true
            activeFocusOnTab: true   // default is false; Tab must reach the next field
            verticalAlignment: TextInput.AlignVCenter
            Keys.onReturnPressed: form.submitted()
            Keys.onEnterPressed: form.submitted()
        }
        Text {
            id: fieldPlaceholder
            anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(1, 1, 1, 0.3)
            font.pointSize: 9
            visible: fieldInput.text === ""
            opacity: fieldInput.activeFocus ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
    }

    // Small square button that opens a file picker for the field beside it.
    component PickButton: Rectangle {
        id: pickBtn
        property string glyph: "\uf07c"
        signal requestPick()
        width: 30
        height: 30
        radius: 6
        color: pickArea.pressed ? Qt.rgba(1, 1, 1, 0.24)
            : pickArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
        Behavior on color { ColorAnimation { duration: 100 } }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)

        Text {
            anchors.centerIn: parent
            text: pickBtn.glyph
            font.family: form.shell.iconFont
            font.pointSize: 11
            color: form.shell.shelfFgColor
        }
        MouseArea {
            id: pickArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pickBtn.requestPick()
        }
    }

    Column {
        id: fields
        anchors { left: parent.left; right: parent.right }
        spacing: 6

        FieldBox {
            id: titleBox
            placeholder: "Title"
        }
        FieldBox {
            id: authorBox
            placeholder: "Author"
        }
        Row {
            width: parent.width
            spacing: 6
            Rectangle {
                width: 30
                height: 30
                radius: 6
                color: form.safeColor(colourBox.text)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                anchors.verticalCenter: parent.verticalCenter
            }
            FieldBox {
                id: colourBox
                width: parent.width - 36
                placeholder: "Colour"
            }
        }
        Row {
            width: parent.width
            spacing: 6
            FieldBox {
                id: patternBox
                width: (parent.width - 6) / 2
                placeholder: "Pattern ID"
                validator: IntValidator { bottom: 0; top: 3 }
            }
            FieldBox {
                id: heightBox
                width: (parent.width - 6) / 2
                placeholder: "Height"
                validator: IntValidator { bottom: 160; top: 290 }
            }
        }
        Row {
            width: parent.width
            spacing: 6
            FieldBox {
                id: urlBox
                width: parent.width - 36
                placeholder: "Cover file"
            }
            PickButton {
                glyph: "\uf03e"
                anchors.verticalCenter: parent.verticalCenter
                onRequestPick: form.coverRequested()
            }
        }
        Row {
            width: parent.width
            spacing: 6
            FieldBox {
                id: fileBox
                width: parent.width - 36
                placeholder: "Book file"
            }
            PickButton {
                glyph: "\uf1c9"
                anchors.verticalCenter: parent.verticalCenter
                onRequestPick: form.fileRequested()
            }
        }
    }

    function safeColor(c) {
        if (!c) return Qt.rgba(1, 1, 1, 0.08)
        try { return Qt.color(c) } catch (e) { return Qt.rgba(1, 1, 1, 0.08) }
    }
}
