import QtQuick
import Qt.labs.folderlistmodel
import Quickshell

// Built-in file picker panel. The Qt/portal FileDialog silently fails to
// open when parented to a layer-shell window (no window ever maps), so the
// book picker browses the filesystem with this instead: folders first,
// filtered files below, quick jumps for common places.
Rectangle {
    id: browser

    required property var shell

    property bool open: false
    property var nameFilters: ["*"]
    property string currentDir: homeDir
    signal picked(string path)
    signal cancelled()

    readonly property string homeDir: Quickshell.env("HOME") || "/"

    readonly property var places: [
        { name: "Home", path: homeDir },
        { name: "Dokumente", path: homeDir + "/Dokumente" },
        { name: "Downloads", path: homeDir + "/Downloads" },
        { name: "Bilder", path: homeDir + "/Bilder" },
        { name: "Desktop", path: homeDir + "/Desktop" }
    ]

    function show(filters) {
        nameFilters = filters
        open = true    // keeps the last directory between consecutive picks
    }

    function hide() {
        open = false
        cancelled()
    }

    function parentOf(dir) {
        var i = dir.lastIndexOf("/")
        if (i < 0) return dir
        if (i === 0) return dir.length > 1 ? "/" : dir
        return dir.substring(0, i)
    }

    function urlToPath(u) {
        var s = u.toString()
        if (s.indexOf("file://") === 0) {
            var p = s.substring(7)
            try { return decodeURIComponent(p) } catch (e) { return p }
        }
        return s
    }

    function pathToUrl(p) {
        return "file://" + encodeURIComponent(p).replace(/%2F/gi, "/")
    }

    visible: open
    // Pop-in (fade + slight scale) matching the picker's other transitions;
    // closing stays instant like the popup itself.
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.96
    transformOrigin: Item.Center
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    radius: 10
    color: shell.shelfBgColor
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.1)

    // Modal sink: without it, clicks/hover on the panel's padding and other
    // non-widget areas fell through to the shelf — deselecting, dragging or
    // even opening books behind the "dialog". Declared first, so every real
    // control above it still gets its own events.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }

    // Top-level inline component (nested declarations break signal lookup).
    component NavButton: Rectangle {
        property string glyph: ""
        signal activated()
        width: 26
        height: 26
        radius: 6
        color: navArea.pressed ? Qt.rgba(1, 1, 1, 0.2)
            : navArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            font.family: browser.shell.iconFont
            font.pointSize: 11
            color: browser.shell.shelfFgColor
        }
        MouseArea {
            id: navArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Row {
            width: parent.width
            spacing: 6

            NavButton {
                glyph: "\uf062"
                anchors.verticalCenter: parent.verticalCenter
                onActivated: browser.currentDir = browser.parentOf(browser.currentDir)
            }
            Text {
                width: parent.width - 64
                anchors.verticalCenter: parent.verticalCenter
                text: browser.currentDir
                font.pointSize: 9
                color: Qt.rgba(1, 1, 1, 0.6)
                elide: Text.ElideMiddle
            }
            NavButton {
                glyph: "\uf00d"
                anchors.verticalCenter: parent.verticalCenter
                onActivated: browser.hide()
            }
        }

        Row {
            width: parent.width
            spacing: 4
            Repeater {
                model: browser.places
                delegate: Rectangle {
                    required property var modelData
                    width: placeText.implicitWidth + 14
                    height: 22
                    radius: 6
                    color: placeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.05)
                    Text {
                        id: placeText
                        anchors.centerIn: parent
                        text: parent.modelData.name
                        font.pointSize: 8
                        color: browser.shell.shelfFgColor
                    }
                    MouseArea {
                        id: placeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: browser.currentDir = parent.modelData.path
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: parent.height - 64
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.25)
            clip: true

            ListView {
                id: fileList
                anchors.fill: parent
                anchors.margins: 4
                spacing: 1
                clip: true

                model: FolderListModel {
                    id: folders
                    showDirsFirst: true
                    showDotAndDotDot: false
                    caseSensitive: false
                    folder: browser.pathToUrl(browser.currentDir)
                    nameFilters: browser.nameFilters
                }

                Text {
                    anchors.centerIn: parent
                    text: "Cannot read folder"
                    font.pointSize: 9
                    color: Qt.rgba(1, 1, 1, 0.35)
                    visible: folders.status !== FolderListModel.Ready
                }

                Text {
                    anchors.centerIn: parent
                    text: "Empty folder"
                    font.pointSize: 9
                    color: Qt.rgba(1, 1, 1, 0.35)
                    visible: folders.status === FolderListModel.Ready && fileList.count === 0
                }

                delegate: Rectangle {
                    required property int index
                    required property string fileName
                    required property url fileUrl
                    required property bool fileIsDir
                    width: fileList.width
                    height: 28
                    radius: 4
                    color: rowArea.pressed ? Qt.rgba(1, 1, 1, 0.18)
                        : rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1)
                        : (index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.fileIsDir ? "\uf07b" : "\uf016"
                        font.family: browser.shell.iconFont
                        font.pointSize: 10
                        color: parent.fileIsDir ? browser.shell.shelfFgColor : Qt.rgba(1, 1, 1, 0.5)
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 30
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.fileName
                        font.pointSize: 9
                        color: parent.fileIsDir ? browser.shell.shelfFgColor : Qt.rgba(1, 1, 1, 0.8)
                        elide: Text.ElideMiddle
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (parent.fileIsDir)
                                browser.currentDir = browser.urlToPath(parent.fileUrl)
                            else
                                browser.picked(browser.urlToPath(parent.fileUrl))
                        }
                    }
                }
            }
        }
    }
}
