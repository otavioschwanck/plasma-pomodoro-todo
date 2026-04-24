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
    property string taskReminder: ""   // ISO datetime string, "" = none

    property bool editing: false
    property bool editingDesc: false

    signal toggleDone()
    signal toggleExpanded()
    signal titleEdited(string newTitle)
    signal descriptionEdited(string newDesc)
    signal reminderSet(string isoDatetime)
    signal removeRequested()
    signal editingStarted()
    signal editingEnded()

    implicitHeight: col.implicitHeight
    // Delegate width is controlled by the ListView; keeping an intrinsic width
    // here makes the popup resize itself based on whichever task is visible.
    implicitWidth:  0

    onEditingChanged: {
        editing ? editingStarted() : editingEnded()
        if (editing) Qt.callLater(function() {
            titleField.forceActiveFocus()
            titleField.selectAll()
        })
    }

    onEditingDescChanged: {
        editingDesc ? editingStarted() : editingEnded()
        if (editingDesc) {
            descArea.text = root.taskDescription   // fresh copy, breaks stale binding
            Qt.callLater(function() { descArea.forceActiveFocus() })
        }
    }

    onTaskExpandedChanged: {
        if (!taskExpanded) editingDesc = false
    }

    // ── Reminder picker popup ─────────────────────────────────────────────────
    QQC2.Popup {
        id: reminderPopup
        parent: QQC2.Overlay.overlay
        x: Math.round((parent.width  - width)  / 2)
        y: Math.round((parent.height - height) / 2)
        modal: true
        padding: Kirigami.Units.largeSpacing
        width: Kirigami.Units.gridUnit * 22

        onOpened: root.editingStarted()
        onClosed: root.editingEnded()

        // Cell width for calendar grid: split available content width into 7 columns
        readonly property real cellW: (width - 2 * padding) / 7
        readonly property real cellH: Math.max(cellW * 0.85, Kirigami.Units.gridUnit * 1.5)

        // Picker state
        property int selYear:  0
        property int selMonth: 0   // 0-based (JS convention)
        property int selDay:   0
        property int calYear:  0
        property int calMonth: 0   // 0-based

        // Day-of-week headers respecting locale (Qt firstDayOfWeek: Mon=1..Sun=7)
        readonly property var dayHeaders: {
            var loc = Qt.locale()
            var fdow = loc.firstDayOfWeek   // Qt enum: Mon=1,..,Sat=6,Sun=7
            var h = []
            for (var i = 0; i < 7; i++) {
                // Cycle through 1-7 starting at fdow
                var dow = ((fdow - 1 + i) % 7) + 1
                var name = loc.dayName(dow, Locale.ShortFormat)
                h.push(name.length > 2 ? name.substring(0, 2) : name)
            }
            return h
        }

        // Compute 42-day grid (6 weeks) for current calMonth/calYear
        readonly property var calDays: {
            var m = calMonth; var y = calYear   // read to track binding
            return reminderPopup._buildDays(m, y)
        }

        function _buildDays(month, year) {
            var loc = Qt.locale()
            var fdow = loc.firstDayOfWeek          // Qt: Mon=1,..,Sun=7
            var jsFdow = (fdow === 7) ? 0 : fdow   // convert Sun→0 for JS getDay()
            var firstDay = new Date(year, month, 1)
            var startDow = firstDay.getDay()        // JS: 0=Sun..6=Sat
            var offset = (startDow - jsFdow + 7) % 7
            var today = new Date()
            var todayStr = today.toDateString()
            var days = []
            for (var i = 0; i < 42; i++) {
                var d = new Date(year, month, 1 - offset + i)
                days.push({
                    y: d.getFullYear(), m: d.getMonth(), d: d.getDate(),
                    cur: d.getMonth() === month,
                    tod: d.toDateString() === todayStr
                })
            }
            return days
        }

        function initFromReminder() {
            var now = new Date()
            var d = root.taskReminder.length > 0 ? new Date(root.taskReminder) : now
            if (isNaN(d.getTime())) d = now
            selYear  = d.getFullYear()
            selMonth = d.getMonth()
            selDay   = d.getDate()
            calYear  = selYear
            calMonth = selMonth
            hourSpin.value = root.taskReminder.length > 0 ? d.getHours()   : 9
            minSpin.value  = root.taskReminder.length > 0 ? d.getMinutes() : 0
        }

        function _pick(d) {
            selYear = d.getFullYear(); selMonth = d.getMonth(); selDay = d.getDate()
            calYear = selYear; calMonth = selMonth
        }

        function buildIso() {
            return new Date(selYear, selMonth, selDay,
                            hourSpin.value, minSpin.value, 0, 0).toISOString()
        }

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing

            // ── Quick buttons ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Button {
                    Layout.fillWidth: true; text: i18n("Today")
                    onClicked: {
                        var d = new Date()
                        d.setHours(d.getHours() + 1)   // 1 h from now (rolls to tomorrow if past 23:00)
                        reminderPopup._pick(d)
                        hourSpin.value = d.getHours()
                        minSpin.value  = d.getMinutes()
                    }
                }
                PlasmaComponents3.Button {
                    Layout.fillWidth: true; text: i18n("Tomorrow")
                    onClicked: { var d = new Date(); d.setDate(d.getDate() + 1); reminderPopup._pick(d) }
                }
            }

            // ── Month navigation ───────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.ToolButton {
                    icon.name: "go-previous"; flat: true
                    implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    onClicked: {
                        if (reminderPopup.calMonth === 0) { reminderPopup.calMonth = 11; reminderPopup.calYear-- }
                        else reminderPopup.calMonth--
                    }
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; font.bold: true
                    text: Qt.locale().monthName(reminderPopup.calMonth, Locale.LongFormat)
                          + "  " + reminderPopup.calYear
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "go-next"; flat: true
                    implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    onClicked: {
                        if (reminderPopup.calMonth === 11) { reminderPopup.calMonth = 0; reminderPopup.calYear++ }
                        else reminderPopup.calMonth++
                    }
                }
            }

            // ── Day-of-week header ─────────────────────────────────────────
            Row {
                Layout.fillWidth: true
                Repeater {
                    model: reminderPopup.dayHeaders
                    PlasmaComponents3.Label {
                        width: reminderPopup.cellW
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: Kirigami.Units.gridUnit * 0.75
                        opacity: 0.6
                    }
                }
            }

            // ── Day grid ───────────────────────────────────────────────────
            Grid {
                columns: 7
                Layout.fillWidth: true

                Repeater {
                    model: reminderPopup.calDays
                    delegate: Rectangle {
                        width:  reminderPopup.cellW
                        height: reminderPopup.cellH
                        radius: Kirigami.Units.smallSpacing

                        readonly property bool isSelected:
                            modelData.y === reminderPopup.selYear &&
                            modelData.m === reminderPopup.selMonth &&
                            modelData.d === reminderPopup.selDay

                        color: isSelected
                             ? Kirigami.Theme.highlightColor
                             : (dayHov.containsMouse && modelData.cur
                                ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                          Kirigami.Theme.highlightColor.g,
                                          Kirigami.Theme.highlightColor.b, 0.2)
                                : "transparent")

                        // Dot under today
                        Rectangle {
                            visible: modelData.tod && !parent.isSelected
                            width: 4; height: 4; radius: 2
                            color: Kirigami.Theme.highlightColor
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                        }

                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            text: modelData.d
                            font.pixelSize: Kirigami.Units.gridUnit * 0.85
                            opacity: modelData.cur ? 1.0 : 0.25
                            color: parent.isSelected
                                 ? Kirigami.Theme.highlightedTextColor
                                 : Kirigami.Theme.textColor
                        }

                        HoverHandler {
                            id: dayHov
                            cursorShape: modelData.cur ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler {
                            enabled: modelData.cur
                            onTapped: {
                                reminderPopup.selYear  = modelData.y
                                reminderPopup.selMonth = modelData.m
                                reminderPopup.selDay   = modelData.d
                            }
                        }
                    }
                }
            }

            // ── Time picker ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label { text: i18n("Time:") }
                Item { Layout.fillWidth: true }
                QQC2.SpinBox {
                    id: hourSpin; from: 0; to: 23
                    textFromValue: function(v) { return v < 10 ? "0" + v : String(v) }
                    valueFromText: function(t) { return parseInt(t) || 0 }
                }
                PlasmaComponents3.Label { text: ":" }
                QQC2.SpinBox {
                    id: minSpin; from: 0; to: 59; stepSize: 5
                    textFromValue: function(v) { return v < 10 ? "0" + v : String(v) }
                    valueFromText: function(t) { return parseInt(t) || 0 }
                }
            }

            // ── Action buttons ─────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                PlasmaComponents3.Button {
                    text: i18n("Clear"); icon.name: "edit-clear"
                    visible: root.taskReminder.length > 0
                    onClicked: { root.reminderSet(""); reminderPopup.close() }
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Button {
                    text: i18n("Cancel")
                    onClicked: reminderPopup.close()
                }
                PlasmaComponents3.Button {
                    text: i18n("Set"); icon.name: "appointment-new"; highlighted: true
                    enabled: reminderPopup.selDay > 0
                    onClicked: { root.reminderSet(reminderPopup.buildIso()); reminderPopup.close() }
                }
            }
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────────
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

        // ── Expanded detail area ──────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin:   Kirigami.Units.gridUnit + Kirigami.Units.smallSpacing
            Layout.rightMargin:  Kirigami.Units.smallSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            visible: taskExpanded && !root.editing
            spacing: 2

            // Read mode: markdown + edit button
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

            // Edit mode: TextArea + Save button
            // Blur → discard | ESC / Save button → save
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.editingDesc
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextArea {
                    id: descArea
                    Layout.fillWidth: true
                    placeholderText: i18n("Add a description… (Markdown supported)")
                    wrapMode: TextEdit.WordWrap
                    implicitHeight: Math.max(
                        Kirigami.Units.gridUnit * 4,
                        contentHeight + topPadding + bottomPadding
                    )

                    // Blur → save (never discard)
                    onActiveFocusChanged: {
                        if (!activeFocus && root.editingDesc) {
                            root.descriptionEdited(descArea.text)
                            root.editingDesc = false
                        }
                    }

                    // ESC → save and close
                    Keys.onEscapePressed: {
                        root.descriptionEdited(descArea.text)
                        root.editingDesc = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Button {
                        text: i18n("Save")
                        icon.name: "document-save"
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            root.descriptionEdited(descArea.text)
                            root.editingDesc = false
                        }
                    }
                }
            }

            // ── Reminder row ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                visible: !root.editingDesc
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "appointment-new"
                    Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    opacity: root.taskReminder.length > 0 ? 1.0 : 0.45
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: {
                        if (!root.taskReminder) return i18n("Set reminder…")
                        var d = new Date(root.taskReminder)
                        if (isNaN(d.getTime())) return i18n("Set reminder…")
                        return Qt.formatDateTime(d, "ddd, d MMM yyyy  HH:mm")
                    }
                    opacity: root.taskReminder.length > 0 ? 1.0 : 0.45
                    font.italic: root.taskReminder.length === 0
                    TapHandler {
                        onTapped: { reminderPopup.initFromReminder(); reminderPopup.open() }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "edit-clear"
                    flat: true
                    visible: root.taskReminder.length > 0
                    implicitWidth:  Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    onClicked: root.reminderSet("")
                    QQC2.ToolTip.text: i18n("Clear reminder")
                    QQC2.ToolTip.visible: hovered
                }
            }
        }
    }
}
