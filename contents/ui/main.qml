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
    property string timerMode: "work"   // "work" | "shortBreak" | "longBreak"
    property int doneCount: 0

    function formatTime(secs) {
        var m = Math.floor(secs / 60)
        var s = secs % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function modeLabel() {
        if (timerMode === "work")       return "Focus"
        if (timerMode === "shortBreak") return "Short Break"
        return "Long Break"
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

    function startTimer()  { pomodoroTimer.start(); isRunning = true  }
    function pauseTimer()  { pomodoroTimer.stop();  isRunning = false }

    function resetCurrent() {
        pomodoroTimer.stop()
        isRunning = false
        remainingSeconds = modeDuration()
    }

    function resetAll() {
        pomodoroTimer.stop()
        isRunning = false
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

    function clearAllTasks() {
        taskModel.clear()
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
        plasmoid.setAction("startPause",    "Start",           "media-playback-start")
        plasmoid.setAction("resetCurrent",  "Reset Current",   "media-playback-stop")
        plasmoid.setAction("resetAll",      "Reset All",       "view-refresh")
        plasmoid.setAction("skip",          "Skip",            "media-skip-forward")
        plasmoid.setAction("clearAllTasks", "Clear All Tasks", "edit-clear-all")
    }

    onIsRunningChanged: {
        var act = plasmoid.action("startPause")
        if (act) {
            act.text      = isRunning ? "Pause" : "Start"
            act.icon.name = isRunning ? "media-playback-pause" : "media-playback-start"
        }
    }

    function action_startPause()    { isRunning ? pauseTimer() : startTimer() }
    function action_resetCurrent()  { resetCurrent() }
    function action_resetAll()      { resetAll() }
    function action_skip()          { pauseTimer(); advanceMode() }
    function action_clearAllTasks() { clearAllTasks() }

    // Re-sync duration if config changes while idle
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
                // Notify with current mode (before advance)
                var msg = root.timerMode === "work"
                          ? "Focus session done! Time for a break."
                          : "Break over. Back to work!"
                root.sendNotification("Pomodoro", msg)
                root.advanceMode()
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

    function loadTasks() {
        try {
            var arr = JSON.parse(plasmoid.configuration.tasks)
            taskModel.clear()
            arr.forEach(function(t) {
                taskModel.append({
                    title:       t.title       || "",
                    description: t.description || "",
                    done:        t.done        || false,
                    expanded:    false
                })
            })
        } catch(e) {
            taskModel.clear()
        }
        updateDoneCount()
    }

    function saveTasks() {
        var arr = []
        for (var i = 0; i < taskModel.count; i++) {
            var t = taskModel.get(i)
            arr.push({ title: t.title, description: t.description, done: t.done })
        }
        plasmoid.configuration.tasks = JSON.stringify(arr)
        updateDoneCount()
    }

    function addTask(title) {
        title = (title || "").trim()
        if (title.length === 0) return false
        taskModel.append({ title: title, description: "", done: false, expanded: false })
        saveTasks()
        return true
    }

    // ─── Compact representation (panel) ──────────────────────────────────────
    compactRepresentation: Item {
        // Width: enough for content + horizontal breathing room
        readonly property string mode: plasmoid.configuration.trayDisplayMode
        readonly property bool showTimer: root.isRunning && mode !== "iconOnly"
        readonly property bool showIcon:  !root.isRunning || mode !== "timerOnly"

        implicitWidth: {
            var w = 0
            if (showIcon)  w += Kirigami.Units.iconSizes.medium
            if (showIcon && showTimer) w += Kirigami.Units.smallSpacing
            if (showTimer) w += timerLabel.implicitWidth + 4  // dot + spacing
            return w + Kirigami.Units.smallSpacing * 2
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing / 2

            Kirigami.Icon {
                visible: parent.parent.showIcon
                source: plasmoid.configuration.trayIcon || "appointment-new"
                Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }

            // Colored dot (only shown alongside icon)
            Rectangle {
                visible: parent.parent.showTimer && parent.parent.showIcon
                width: 6; height: 6; radius: 3
                color: root.modeColor()
            }

            PlasmaComponents3.Label {
                id: timerLabel
                visible: parent.parent.showTimer
                text: root.formatTime(root.remainingSeconds)
                color: root.modeColor()
                font.bold: true
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.9)
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
                    text: "Reset Current"
                    icon.name: "media-playback-stop"
                    onClicked: root.resetCurrent()
                    QQC2.ToolTip.text: "Reset this step's timer"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 800
                }

                PlasmaComponents3.Button {
                    text: root.isRunning ? "Pause" : "Start"
                    icon.name: root.isRunning ? "media-playback-pause" : "media-playback-start"
                    highlighted: true
                    onClicked: root.isRunning ? root.pauseTimer() : root.startTimer()
                }

                PlasmaComponents3.Button {
                    text: "Skip"
                    icon.name: "media-skip-forward"
                    onClicked: { root.pauseTimer(); root.advanceMode() }
                    QQC2.ToolTip.text: "Skip to next step"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 800
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Kirigami.Units.smallSpacing

                PlasmaComponents3.Button {
                    text: "Reset All"
                    icon.name: "view-refresh"
                    onClicked: root.resetAll()
                    QQC2.ToolTip.text: "Reset timer and all sessions"
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

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.Label {
                    text: "Tasks"
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
                    visible: taskModel.count > 0
                    onClicked: clearConfirmDialog.open()
                    QQC2.ToolTip.text: "Clear all tasks"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 600
                }
            }

            QQC2.Dialog {
                id: clearConfirmDialog
                title: "Clear all tasks?"
                modal: true
                anchors.centerIn: parent

                contentItem: PlasmaComponents3.Label {
                    text: "This will permanently remove all " + taskModel.count + " task(s)."
                    wrapMode: Text.WordWrap
                    padding: Kirigami.Units.largeSpacing
                }

                footer: QQC2.DialogButtonBox {
                    QQC2.Button {
                        text: "Clear all"
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.DestructiveRole
                        onClicked: { root.clearAllTasks(); clearConfirmDialog.close() }
                    }
                    QQC2.Button {
                        text: "Cancel"
                        QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                        onClicked: clearConfirmDialog.close()
                    }
                }
            }

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

                        onToggleDone: {
                            taskModel.setProperty(index, "done", !model.done)
                            root.saveTasks()
                        }
                        onToggleExpanded: {
                            taskModel.setProperty(index, "expanded", !model.expanded)
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

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TextField {
                    id: newTaskField
                    Layout.fillWidth: true
                    placeholderText: "Add a task…"
                    onAccepted: { if (root.addTask(text)) text = "" }
                }

                PlasmaComponents3.Button {
                    text: "Add"
                    icon.name: "list-add"
                    enabled: newTaskField.text.trim().length > 0
                    onClicked: { if (root.addTask(newTaskField.text)) newTaskField.text = "" }
                }
            }
        }
    }
}
