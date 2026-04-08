import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.notification
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ─── Timer state ─────────────────────────────────────────────────────────
    property int remainingSeconds: plasmoid.configuration.pomodoroMinutes * 60
    property bool isRunning: false
    property int sessionCount: 0
    property string timerMode: "work"
    property int doneCount: 0
    property bool isPaused: false   // true only after an explicit Pause; false after Start/Reset

    // Resolved at runtime so the path is always correct regardless of install location
    readonly property string logoUrl: Qt.resolvedUrl("../assets/logo.svg").toString()

    // ─── Workspace / task state ───────────────────────────────────────────────
    property int currentWorkspace: 0
    property var workspacesData: []

    function formatTime(secs) {
        var m = Math.floor(secs / 60)
        var s = secs % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function modeLabel() {
        if (timerMode === "work")       return i18n("Focus")
        if (timerMode === "shortBreak") return i18n("Short Break")
        return i18n("Long Break")
    }

    function modeColor() {
        return timerMode === "work"
            ? plasmoid.configuration.focusColor
            : plasmoid.configuration.breakColor
    }

    function modeDuration() {
        if (timerMode === "work")       return plasmoid.configuration.pomodoroMinutes * 60
        if (timerMode === "shortBreak") return plasmoid.configuration.shortBreakMinutes * 60
        return plasmoid.configuration.longBreakMinutes * 60
    }

    function startTimer()  { pomodoroTimer.start(); isRunning = true;  isPaused = false }
    function pauseTimer()  { pomodoroTimer.stop();  isRunning = false; isPaused = true  }

    function resetCurrent() {
        pomodoroTimer.stop()
        isRunning = false
        isPaused = false
        remainingSeconds = modeDuration()
    }

    function resetAll() {
        pomodoroTimer.stop()
        isRunning = false
        isPaused = false
        sessionCount = 0
        timerMode = "work"
        remainingSeconds = plasmoid.configuration.pomodoroMinutes * 60
    }

    function advanceMode() {
        if (timerMode === "work") {
            sessionCount++
            timerMode = (sessionCount % 4 === 0) ? "longBreak" : "shortBreak"
        } else {
            timerMode = "work"
        }
        remainingSeconds = modeDuration()
    }

    function currentIcon() {
        if (!root.isRunning && root.isPaused)  return plasmoid.configuration.pausedIcon || "media-playback-pause"
        if (!root.isRunning && !root.isPaused) return plasmoid.configuration.idleIcon   || root.logoUrl
        if (root.timerMode === "shortBreak")   return plasmoid.configuration.shortBreakIcon || "face-sleeping"
        if (root.timerMode === "longBreak")    return plasmoid.configuration.longBreakIcon  || "face-sleeping"
        return plasmoid.configuration.focusIcon || "appointment-new"
    }

    function clearAllTasks() {
        for (var i = taskModel.count - 1; i >= 0; i--) {
            if (taskModel.get(i).done) taskModel.remove(i)
        }
        saveTasks()
    }

    // ─── Notifications ────────────────────────────────────────────────────────
    Notification {
        id: timerNotif
        componentName: "plasma_workspace"
        eventId:       "notification"
        title:         "Pomodoro"
        urgency:       Notification.NormalUrgency
    }

    function sendNotification(title, body) {
        if (!plasmoid.configuration.notificationsEnabled) return
        timerNotif.title = title
        timerNotif.text  = body
        timerNotif.sendEvent()
    }

    // ─── Context menu (right-click on tray) ──────────────────────────────────
    Component.onCompleted: {
        loadTasks()

        plasmoid.setAction("startPause",    i18n("Start"),           "media-playback-start")
        plasmoid.setAction("resetCurrent",  i18n("Reset Current"),   "media-playback-stop")
        plasmoid.setAction("resetAll",      i18n("Reset All"),       "view-refresh")
        plasmoid.setAction("skip",          i18n("Skip"),            "media-skip-forward")
        plasmoid.setAction("clearAllTasks", i18n("Clear Completed Tasks"), "edit-clear-all")

        plasmoid.action("startPause").triggered.connect(function()    { root.isRunning ? root.pauseTimer() : root.startTimer() })
        plasmoid.action("resetCurrent").triggered.connect(function()  { root.resetCurrent() })
        plasmoid.action("resetAll").triggered.connect(function()      { root.resetAll() })
        plasmoid.action("skip").triggered.connect(function()          { root.pauseTimer(); root.advanceMode() })
        plasmoid.action("clearAllTasks").triggered.connect(function() { root.clearAllTasks() })
    }

    onIsRunningChanged: {
        var act = plasmoid.action("startPause")
        if (act) {
            act.text      = isRunning ? i18n("Pause") : i18n("Start")
            act.icon.name = isRunning ? "media-playback-pause" : "media-playback-start"
        }
    }

    Connections {
        target: plasmoid.configuration
        function onPomodoroMinutesChanged()   { if (!root.isRunning && root.timerMode === "work")       root.remainingSeconds = root.modeDuration() }
        function onShortBreakMinutesChanged() { if (!root.isRunning && root.timerMode === "shortBreak") root.remainingSeconds = root.modeDuration() }
        function onLongBreakMinutesChanged()  { if (!root.isRunning && root.timerMode === "longBreak")  root.remainingSeconds = root.modeDuration() }
    }

    Timer {
        id: pomodoroTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.remainingSeconds > 0) {
                root.remainingSeconds--
            } else {
                stop()
                root.isRunning = false
                var msg = root.timerMode === "work"
                          ? i18n("Focus session done! Time for a break.")
                          : i18n("Break over. Back to work!")
                root.sendNotification("Pomodoro", msg)
                root.advanceMode()
                if (plasmoid.configuration.autoStartNext) root.startTimer()
            }
        }
    }

    // ─── Task model ───────────────────────────────────────────────────────────
    ListModel { id: taskModel }

    function updateDoneCount() {
        var n = 0
        for (var i = 0; i < taskModel.count; i++)
            if (taskModel.get(i).done) n++
        doneCount = n
    }

    // Populate taskModel from workspacesData[currentWorkspace]
    function reloadTaskModel() {
        taskModel.clear()
        var ws = workspacesData[currentWorkspace]
        if (!ws) return
        ;(ws.tasks || []).forEach(function(t) {
            taskModel.append({
                title:       t.title       || "",
                description: t.description || "",
                done:        t.done        || false,
                expanded:    false,
                editDesc:    false
            })
        })
    }

    // Sync taskModel → workspacesData[currentWorkspace] (deep-copy to trigger bindings)
    function syncCurrentWorkspace() {
        if (workspacesData.length === 0) return
        var tasks = []
        for (var i = 0; i < taskModel.count; i++) {
            var t = taskModel.get(i)
            tasks.push({ title: t.title, description: t.description, done: t.done })
        }
        var copy = JSON.parse(JSON.stringify(workspacesData))
        copy[currentWorkspace].tasks = tasks
        workspacesData = copy
    }

    function loadTasks() {
        try {
            var raw = JSON.parse(plasmoid.configuration.tasks)
            if (Array.isArray(raw) && raw.length > 0) {
                // New format: [{name, tasks}, ...]  vs old format: [{title, done}, ...]
                if (raw[0].hasOwnProperty('name') && raw[0].hasOwnProperty('tasks')) {
                    workspacesData = raw
                } else {
                    // Migrate old flat task list into a single default workspace
                    workspacesData = [{ name: "Default", tasks: raw }]
                }
            } else {
                workspacesData = [{ name: "Default", tasks: [] }]
            }
        } catch(e) {
            workspacesData = [{ name: "Default", tasks: [] }]
        }
        currentWorkspace = 0
        reloadTaskModel()
        updateDoneCount()
    }

    function saveTasks() {
        syncCurrentWorkspace()
        plasmoid.configuration.tasks = JSON.stringify(workspacesData)
        updateDoneCount()
    }

    function addTask(title) {
        title = (title || "").trim()
        if (title.length === 0) return false
        var autoExpand = plasmoid.configuration.autoExpandNewTask
        taskModel.append({
            title:       title,
            description: "",
            done:        false,
            expanded:    autoExpand,
            editDesc:    autoExpand
        })
        saveTasks()
        return true
    }

    function switchWorkspace(index) {
        if (index === currentWorkspace) return
        saveTasks()
        currentWorkspace = index
        reloadTaskModel()
        updateDoneCount()
    }

    function addWorkspace(name) {
        saveTasks()
        var copy = JSON.parse(JSON.stringify(workspacesData))
        copy.push({ name: name.trim(), tasks: [] })
        workspacesData = copy
        currentWorkspace = copy.length - 1
        taskModel.clear()
        plasmoid.configuration.tasks = JSON.stringify(workspacesData)
        updateDoneCount()
    }

    function renameWorkspace(index, newName) {
        saveTasks()
        var copy = JSON.parse(JSON.stringify(workspacesData))
        copy[index].name = newName.trim()
        workspacesData = copy
        plasmoid.configuration.tasks = JSON.stringify(workspacesData)
    }

    function removeWorkspace(index) {
        if (workspacesData.length <= 1) return
        var copy = JSON.parse(JSON.stringify(workspacesData))
        copy.splice(index, 1)
        workspacesData = copy
        currentWorkspace = Math.min(currentWorkspace, copy.length - 1)
        reloadTaskModel()
        plasmoid.configuration.tasks = JSON.stringify(workspacesData)
        updateDoneCount()
    }

    // ─── Compact representation (panel) ──────────────────────────────────────
    compactRepresentation: Item {
        id: compactRoot

        readonly property string displayMode: plasmoid.configuration.trayDisplayMode
        readonly property bool showTimer: root.isRunning && displayMode !== "iconOnly"
        readonly property bool showIcon:  !root.isRunning || displayMode !== "timerOnly"

        TextMetrics {
            id: timerMetrics
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.9)
            font.bold: true
            text: "00:00"
        }

        readonly property real _pad:   Kirigami.Units.smallSpacing * 2
        readonly property real _icon:  Kirigami.Units.iconSizes.medium
        readonly property real _dot:   6 + Kirigami.Units.smallSpacing / 2
        readonly property real _timer: timerMetrics.advanceWidth

        readonly property real desiredWidth: {
            if (displayMode === "iconOnly")  return _icon + _pad
            if (displayMode === "timerOnly") return (showTimer ? _timer : _icon) + _pad
            return showTimer ? (_icon + _dot + _timer + _pad) : (_icon + _pad)
        }

        implicitWidth:         desiredWidth
        Layout.minimumWidth:   desiredWidth
        Layout.preferredWidth: desiredWidth
        Layout.maximumWidth:   desiredWidth

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.MiddleButton)
                    root.isRunning ? root.pauseTimer() : root.startTimer()
                else
                    root.expanded = !root.expanded
            }
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing / 2

            Kirigami.Icon {
                visible: compactRoot.showIcon
                source: root.currentIcon()
                Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                visible: compactRoot.showTimer && compactRoot.showIcon
                width: 6; height: 6; radius: 3
                color: root.modeColor()
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                visible: compactRoot.showTimer
                text: root.formatTime(root.remainingSeconds)
                color: root.modeColor()
                font.bold: true
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.9)
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // ─── Full representation (popup) ─────────────────────────────────────────
    fullRepresentation: ColumnLayout {
        id: fullRep
        implicitWidth: Kirigami.Units.gridUnit * 32
        spacing: 0

        Connections {
            target: root
            function onExpandedChanged() {
                if (root.expanded) Qt.callLater(function() { newTaskField.forceActiveFocus() })
            }
        }

        // ── Pin button row ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: pinBtn.implicitHeight + Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                id: pinBtn
                anchors.right: parent.right
                anchors.rightMargin: Kirigami.Units.smallSpacing
                anchors.verticalCenter: parent.verticalCenter
                icon.name: "window-pin"
                flat: true
                checkable: true
                // Initial state from property; binding breaks after first toggle —
                // that's fine because onToggled keeps the source in sync.
                checked: !root.hideOnWindowDeactivate
                onToggled: root.hideOnWindowDeactivate = !checked
                QQC2.ToolTip.text: checked ? i18n("Auto-close") : i18n("Keep open")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 600
            }
        }

        // ══ Timer section ════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin:    Kirigami.Units.largeSpacing
            Layout.leftMargin:   Kirigami.Units.largeSpacing
            Layout.rightMargin:  Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.modeLabel()
                font.pixelSize: Kirigami.Units.gridUnit * 0.9
                opacity: 0.6
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.formatTime(root.remainingSeconds)
                font.pixelSize: Kirigami.Units.gridUnit * 3.5
                font.bold: true
                color: root.modeColor()
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        width: 8; height: 8; radius: 4
                        color: root.modeColor()
                        opacity: index < (root.sessionCount % 4) ? 1.0 : 0.2
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Button {
                    text: i18n("Reset Current")
                    icon.name: "media-playback-stop"
                    onClicked: root.resetCurrent()
                    QQC2.ToolTip.text: i18n("Reset this step's timer")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 800
                }

                PlasmaComponents3.Button {
                    text: root.isRunning ? i18n("Pause") : i18n("Start")
                    icon.name: root.isRunning ? "media-playback-pause" : "media-playback-start"
                    highlighted: true
                    onClicked: root.isRunning ? root.pauseTimer() : root.startTimer()
                }

                PlasmaComponents3.Button {
                    text: i18n("Skip")
                    icon.name: "media-skip-forward"
                    onClicked: { root.pauseTimer(); root.advanceMode() }
                    QQC2.ToolTip.text: i18n("Skip to next step")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 800
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Kirigami.Units.smallSpacing

                PlasmaComponents3.Button {
                    text: i18n("Reset All")
                    icon.name: "view-refresh"
                    onClicked: root.resetAll()
                    QQC2.ToolTip.text: i18n("Reset timer and all sessions")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 800
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ══ Todo section ═════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            // ── Header row ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.Label {
                    text: i18n("Tasks")
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents3.Label {
                    text: root.doneCount + " / " + taskModel.count
                    opacity: 0.55
                    font.pixelSize: Kirigami.Units.gridUnit * 0.85
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "edit-clear-all"
                    visible: root.doneCount > 0
                    onClicked: clearConfirmDialog.open()
                    QQC2.ToolTip.text: i18n("Clear completed tasks")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 600
                }
            }

            // ── Workspace tab bar ─────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                // Scrollable tab strip
                QQC2.ScrollView {
                    Layout.fillWidth: true
                    implicitHeight: wsTabRow.implicitHeight
                    QQC2.ScrollBar.vertical.policy:   QQC2.ScrollBar.AlwaysOff
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AsNeeded
                    clip: true

                    Row {
                        id: wsTabRow
                        spacing: 2

                        Repeater {
                            model: root.workspacesData.length

                            delegate: Item {
                                id: wsTabDelegate
                                readonly property bool isActive: index === root.currentWorkspace
                                property bool editingName: false

                                // Fixed height across all tabs so the Row stays on one line
                                implicitHeight: Kirigami.Units.iconSizes.small
                                                + Kirigami.Units.smallSpacing * 4
                                implicitWidth:  tabInner.implicitWidth + Kirigami.Units.smallSpacing * 2

                                // Active underline indicator
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left:   parent.left
                                    anchors.right:  parent.right
                                    height: 2
                                    radius: 1
                                    color: Kirigami.Theme.highlightColor
                                    visible: wsTabDelegate.isActive
                                }

                                RowLayout {
                                    id: tabInner
                                    anchors.centerIn: parent
                                    spacing: 2

                                    // Workspace name label
                                    PlasmaComponents3.Label {
                                        visible: !wsTabDelegate.editingName
                                        text: root.workspacesData[index]
                                              ? root.workspacesData[index].name : ""
                                        color: wsTabDelegate.isActive
                                               ? Kirigami.Theme.highlightColor
                                               : Kirigami.Theme.textColor
                                        font.bold: wsTabDelegate.isActive
                                    }

                                    // Inline rename TextField
                                    PlasmaComponents3.TextField {
                                        id: wsNameField
                                        visible: wsTabDelegate.editingName
                                        text: root.workspacesData[index]
                                              ? root.workspacesData[index].name : ""
                                        implicitWidth: Math.max(
                                            Kirigami.Units.gridUnit * 5,
                                            contentWidth + leftPadding + rightPadding + 8
                                        )
                                        Keys.onReturnPressed: wsNameField.commitRename()
                                        Keys.onEscapePressed: wsTabDelegate.editingName = false
                                        onActiveFocusChanged: {
                                            if (!activeFocus && wsTabDelegate.editingName)
                                                wsNameField.commitRename()
                                        }
                                        function commitRename() {
                                            var t = text.trim()
                                            if (t.length > 0) root.renameWorkspace(index, t)
                                            wsTabDelegate.editingName = false
                                        }
                                    }

                                    // Pencil: rename (active, not editing)
                                    PlasmaComponents3.ToolButton {
                                        visible: wsTabDelegate.isActive && !wsTabDelegate.editingName
                                        flat: true
                                        icon.name: "document-edit"
                                        implicitWidth:  Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                                        implicitHeight: implicitWidth
                                        onClicked: {
                                            wsTabDelegate.editingName = true
                                            Qt.callLater(function() {
                                                wsNameField.forceActiveFocus()
                                                wsNameField.selectAll()
                                            })
                                        }
                                        QQC2.ToolTip.text: i18n("Rename workspace")
                                        QQC2.ToolTip.visible: hovered
                                    }

                                    // Trash: delete (active, >1 workspace, not editing)
                                    PlasmaComponents3.ToolButton {
                                        visible: wsTabDelegate.isActive
                                                 && root.workspacesData.length > 1
                                                 && !wsTabDelegate.editingName
                                        flat: true
                                        icon.name: "edit-delete-remove"
                                        implicitWidth:  Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                                        implicitHeight: implicitWidth
                                        onClicked: deleteWsDialog.open()
                                        QQC2.ToolTip.text: i18n("Delete workspace")
                                        QQC2.ToolTip.visible: hovered
                                    }
                                }

                                TapHandler {
                                    enabled: !wsTabDelegate.isActive
                                    onTapped: root.switchWorkspace(index)
                                }
                                HoverHandler {
                                    cursorShape: wsTabDelegate.isActive
                                                 ? Qt.ArrowCursor
                                                 : Qt.PointingHandCursor
                                }
                            }
                        }
                    }
                }

                // "+" button — always visible outside scroll area
                PlasmaComponents3.ToolButton {
                    icon.name: "list-add"
                    flat: true
                    onClicked: { newWsNameField.text = ""; addWsDialog.open() }
                    QQC2.ToolTip.text: i18n("New workspace")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 600
                }
            }

            // ── Dialogs ───────────────────────────────────────────────────

            QQC2.Dialog {
                id: clearConfirmDialog
                title: i18n("Clear completed tasks?")
                modal: true
                anchors.centerIn: parent

                contentItem: PlasmaComponents3.Label {
                    text: i18np("This will permanently remove %1 completed task.",
                                "This will permanently remove %1 completed tasks.",
                                root.doneCount)
                    wrapMode: Text.WordWrap
                    padding: Kirigami.Units.largeSpacing
                }

                footer: QQC2.DialogButtonBox {
                    QQC2.Button {
                        text: i18n("Clear completed")
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.DestructiveRole
                        onClicked: { root.clearAllTasks(); clearConfirmDialog.close() }
                    }
                    QQC2.Button {
                        text: i18n("Cancel")
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                        onClicked: clearConfirmDialog.close()
                    }
                }
            }

            QQC2.Dialog {
                id: addWsDialog
                title: i18n("New Workspace")
                modal: true
                anchors.centerIn: parent

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label { text: i18n("Workspace name:") }
                    PlasmaComponents3.TextField {
                        id: newWsNameField
                        Layout.fillWidth: true
                        placeholderText: i18n("e.g. Work, Personal…")
                        Keys.onReturnPressed: {
                            var n = text.trim()
                            if (n.length > 0) { root.addWorkspace(n); addWsDialog.close() }
                        }
                    }
                }

                footer: QQC2.DialogButtonBox {
                    QQC2.Button {
                        text: i18n("Create")
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.AcceptRole
                        enabled: newWsNameField.text.trim().length > 0
                        onClicked: { root.addWorkspace(newWsNameField.text.trim()); addWsDialog.close() }
                    }
                    QQC2.Button {
                        text: i18n("Cancel")
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                        onClicked: addWsDialog.close()
                    }
                }
            }

            QQC2.Dialog {
                id: deleteWsDialog
                title: i18n("Delete workspace?")
                modal: true
                anchors.centerIn: parent

                contentItem: PlasmaComponents3.Label {
                    text: root.workspacesData[root.currentWorkspace]
                          ? i18n("Delete workspace \"%1\" and all its tasks?",
                                 root.workspacesData[root.currentWorkspace].name)
                          : ""
                    wrapMode: Text.WordWrap
                    padding: Kirigami.Units.largeSpacing
                }

                footer: QQC2.DialogButtonBox {
                    QQC2.Button {
                        text: i18n("Delete")
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.DestructiveRole
                        onClicked: { root.removeWorkspace(root.currentWorkspace); deleteWsDialog.close() }
                    }
                    QQC2.Button {
                        text: i18n("Cancel")
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                        onClicked: deleteWsDialog.close()
                    }
                }
            }

            // ── Task list ─────────────────────────────────────────────────
            QQC2.ScrollView {
                id: taskScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(
                    taskListView.contentHeight,
                    Kirigami.Units.gridUnit * 16
                )
                clip: true
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                ListView {
                    id: taskListView
                    model: taskModel
                    spacing: 2

                    delegate: TodoItem {
                        width: taskListView.width

                        taskTitle:       model.title
                        taskDescription: model.description
                        taskDone:        model.done
                        taskExpanded:    model.expanded

                        // Auto-focus description on newly added tasks when config enabled
                        Component.onCompleted: {
                            if (model.editDesc) {
                                taskModel.setProperty(index, "editDesc", false)
                                Qt.callLater(function() {
                                    taskListView.positionViewAtEnd()
                                    editingDesc = true
                                })
                            }
                        }

                        onToggleDone: {
                            taskModel.setProperty(index, "done", !model.done)
                            root.saveTasks()
                        }
                        onToggleExpanded: {
                            taskModel.setProperty(index, "expanded", !model.expanded)
                        }
                        onTitleEdited: function(newTitle) {
                            taskModel.setProperty(index, "title", newTitle)
                            root.saveTasks()
                        }
                        onDescriptionEdited: function(newDesc) {
                            taskModel.setProperty(index, "description", newDesc)
                            root.saveTasks()
                        }
                        onRemoveRequested: {
                            taskModel.remove(index)
                            root.saveTasks()
                        }
                    }
                }
            }

            // ── Add task row ──────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    id: newTaskField
                    Layout.fillWidth: true
                    placeholderText: i18n("Add a task…")
                    onAccepted: { if (root.addTask(text)) text = "" }
                }

                PlasmaComponents3.Button {
                    text: i18n("Add")
                    icon.name: "list-add"
                    enabled: newTaskField.text.trim().length > 0
                    onClicked: { if (root.addTask(newTaskField.text)) newTaskField.text = "" }
                }
            }
        }
    }
}
