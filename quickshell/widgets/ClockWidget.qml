import QtQuick

Text {
    required property var shell

    color: shell.textColor
    font.pointSize: 10

    function update() {
        text = Qt.formatDateTime(new Date(), "ddd, dd MMM  hh:mm")
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: parent.update()
    }

    Component.onCompleted: update()
}
