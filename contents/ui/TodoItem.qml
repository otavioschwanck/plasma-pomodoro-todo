import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string taskTitle: ""
    property string taskDescription: ""
    property bool taskDone: false
    property bool taskExpanded: false

    signal toggleDone()
    signal toggleExpanded()
    signal descriptionEdited(string newDesc)
    signal removeRequested()

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 0

        // ── Main row ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.CheckBox {
                checked: taskDone
                onToggled: root.toggleDone()
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: taskTitle
                elide: Text.ElideRight
                opacity: taskDone ? 0.45 : 1.0
                font.strikeout: taskDone
            }

            PlasmaComponents3.ToolButton {
                icon.name: taskExpanded ? "go-up" : "go-down"
                flat: true
                implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                onClicked: root.toggleExpanded()
                QQC2.ToolTip.text: taskExpanded ? i18n("Collapse") : i18n("Expand")
                QQC2.ToolTip.visible: hovered
            }

            PlasmaComponents3.ToolButton {
                icon.name: "edit-delete-remove"
                flat: true
                implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                onClicked: root.removeRequested()
                QQC2.ToolTip.text: i18n("Remove task")
                QQC2.ToolTip.visible: hovered
            }
        }

        // ── Description area ──────────────────────────────────────────────
        PlasmaComponents3.TextArea {
            id: descArea
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit + Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            visible: taskExpanded
            text: taskDescription
            placeholderText: i18n("Add a description…")
            wrapMode: TextEdit.WordWrap
            implicitHeight: taskExpanded ? Math.max(Kirigami.Units.gridUnit * 4, contentHeight + topPadding + bottomPadding) : 0

            onTextChanged: saveDebounce.restart()

            Timer {
                id: saveDebounce
                interval: 600
                onTriggered: root.descriptionEdited(descArea.text)
            }
        }
    }
}
