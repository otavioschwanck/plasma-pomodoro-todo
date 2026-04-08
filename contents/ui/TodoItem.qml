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

    property bool editing: false
    property bool editingDesc: false

    signal toggleDone()
    signal toggleExpanded()
    signal titleEdited(string newTitle)
    signal descriptionEdited(string newDesc)
    signal removeRequested()

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    onEditingChanged: {
        if (editing) Qt.callLater(function() {
            titleField.forceActiveFocus()
            titleField.selectAll()
        })
    }

    onEditingDescChanged: {
        if (editingDesc) Qt.callLater(function() { descArea.forceActiveFocus() })
    }

    onTaskExpandedChanged: {
        if (!taskExpanded) editingDesc = false
    }

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
                id: titleLabel
                Layout.fillWidth: true
                visible: !root.editing
                text: taskTitle
                elide: Text.ElideRight
                opacity: taskDone ? 0.45 : 1.0
                font.strikeout: taskDone

                TapHandler { onTapped: root.toggleExpanded() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            PlasmaComponents3.TextField {
                id: titleField
                Layout.fillWidth: true
                visible: root.editing
                text: taskTitle
                placeholderText: i18n("Task title…")

                onAccepted: commitEdit()
                onActiveFocusChanged: {
                    if (!activeFocus && root.editing) commitEdit()
                }
                Keys.onEscapePressed: root.editing = false

                function commitEdit() {
                    var t = text.trim()
                    if (t.length > 0) root.titleEdited(t)
                    root.editing = false
                }
            }

            // NoFocus prevents the button from stealing focus from titleField
            // before onClicked fires (which would flip editing back on)
            PlasmaComponents3.ToolButton {
                icon.name: root.editing ? "dialog-ok" : "document-edit"
                flat: true
                focusPolicy: Qt.NoFocus
                implicitWidth:  Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                onClicked: {
                    if (root.editing) titleField.commitEdit()
                    else              root.editing = true
                }
                QQC2.ToolTip.text: root.editing ? i18n("Save title") : i18n("Edit title")
                QQC2.ToolTip.visible: hovered
            }

            PlasmaComponents3.ToolButton {
                icon.name: taskExpanded ? "go-up" : "go-down"
                flat: true
                visible: !root.editing
                implicitWidth:  Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                onClicked: root.toggleExpanded()
                QQC2.ToolTip.text: taskExpanded ? i18n("Collapse") : i18n("Expand")
                QQC2.ToolTip.visible: hovered
            }

            PlasmaComponents3.ToolButton {
                icon.name: "edit-delete-remove"
                flat: true
                visible: !root.editing
                implicitWidth:  Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                onClicked: root.removeRequested()
                QQC2.ToolTip.text: i18n("Remove task")
                QQC2.ToolTip.visible: hovered
            }
        }

        // ── Description area (visible when expanded) ──────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin:   Kirigami.Units.gridUnit + Kirigami.Units.smallSpacing
            Layout.rightMargin:  Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            visible: taskExpanded && !root.editing
            spacing: 2

            // ── Read mode: rendered markdown ──────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                visible: !root.editingDesc
                spacing: Kirigami.Units.smallSpacing

                Item {
                    Layout.fillWidth: true
                    implicitHeight: taskDescription.length > 0
                        ? mdBox.implicitHeight
                        : addDescLabel.implicitHeight

                    Rectangle {
                        id: mdBox
                        width: parent.width
                        visible: taskDescription.length > 0
                        implicitHeight: mdText.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: Kirigami.Units.smallSpacing
                        color: Qt.rgba(0, 0, 0, 0.08)

                        Text {
                            id: mdText
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top; margins: Kirigami.Units.smallSpacing
                            }
                            textFormat: Text.MarkdownText
                            text: taskDescription
                            wrapMode: Text.WordWrap
                            color: Kirigami.Theme.textColor
                            linkColor: Kirigami.Theme.linkColor
                            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                            HoverHandler {
                                cursorShape: mdText.hoveredLink !== ""
                                             ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        id: addDescLabel
                        width: parent.width
                        visible: taskDescription.length === 0
                        text: i18n("Add description…")
                        opacity: 0.45
                        font.italic: true
                        TapHandler { onTapped: root.editingDesc = true }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "document-edit"
                    flat: true
                    Layout.alignment: Qt.AlignTop
                    implicitWidth:  Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    onClicked: root.editingDesc = true
                    QQC2.ToolTip.text: taskDescription.length > 0
                        ? i18n("Edit description") : i18n("Add description")
                    QQC2.ToolTip.visible: hovered
                }
            }

            // ── Edit mode: raw TextArea ───────────────────────────────────
            PlasmaComponents3.TextArea {
                id: descArea
                Layout.fillWidth: true
                visible: root.editingDesc
                text: taskDescription
                placeholderText: i18n("Add a description… (Markdown supported)")
                wrapMode: TextEdit.WordWrap
                implicitHeight: Math.max(
                    Kirigami.Units.gridUnit * 4,
                    contentHeight + topPadding + bottomPadding
                )

                onTextChanged: saveDebounce.restart()

                onActiveFocusChanged: {
                    if (!activeFocus && root.editingDesc) {
                        root.descriptionEdited(text)
                        root.editingDesc = false
                    }
                }

                Keys.onEscapePressed: {
                    root.descriptionEdited(text)
                    root.editingDesc = false
                }

                Timer {
                    id: saveDebounce
                    interval: 600
                    onTriggered: root.descriptionEdited(descArea.text)
                }
            }
        }
    }
}
