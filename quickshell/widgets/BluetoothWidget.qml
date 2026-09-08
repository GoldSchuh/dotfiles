import QtQuick
import Quickshell
import Quickshell.Bluetooth

Item {
    id: bt

    required property var shell
    property var adapter: Bluetooth.defaultAdapter

    implicitWidth: btButton.implicitWidth
    implicitHeight: shell.barHeight

    Item {
        id: btButton
        width: 26
        height: shell.barHeight

        Text {
            anchors.centerIn: parent
            text: "\uf294"
            font.family: shell.iconFont
            font.pointSize: 10
            color: bt.adapter && bt.adapter.enabled ? shell.textColor : Qt.rgba(1, 1, 1, 0.35)
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (bt.adapter) bt.adapter.enabled = !bt.adapter.enabled
        }
    }
}
