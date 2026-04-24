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
    readonly property string logoUrl: "korg-todo-symbolic"

    // ─── Workspace / task state ───────────────────────────────────────────────
    property int  currentWorkspace: 0
    property var  workspacesData: []
    property int  activeEdits: 0          // incremented by TodoItem while editing
    property bool _pendingSyncReload: false
    property real popupBaseWidth: Kirigami.Units.gridUnit * 32
    property real popupBaseHeight: Kirigami.Units.gridUnit * 28
    property bool popupBaseWidthLocked: false
    property bool popupBaseHeightLocked: false

    onActiveEditsChanged: {
        if (activeEdits === 0 && _pendingSyncReload) {
            _pendingSyncReload = false
            root.loadTasks()
        }
    }

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

    // Reminder notifications: critical urgency + persistent flag so Plasma
    // shows them even over fullscreen apps / Do Not Disturb and never
    // auto-dismisses them. Missed reminders (PC off, etc.) are caught by
    // checkReminders() on startup via loadTasks().
    Notification {
        id: reminderNotif
        componentName: "plasma_workspace"
        eventId:       "notification"
        title:         "Reminder"
        iconName:      "appointment-reminder"
        urgency:       Notification.CriticalUrgency
        autoDelete:    false
        flags:         Notification.Persistent
    }

    function sendNotification(title, body) {
        if (!plasmoid.configuration.notificationsEnabled) return
        timerNotif.title = title
        timerNotif.text  = body
        timerNotif.sendEvent()
    }

    function sendReminderNotification(title, body) {
        if (!plasmoid.configuration.notificationsEnabled) return
        reminderNotif.title = title
        reminderNotif.text  = body
        reminderNotif.sendEvent()
    }

    // Scans ALL workspaces — called by the 30 s timer and immediately after
    // every loadTasks() so a freshly-loaded (or synced) reminder is never missed.
    function checkReminders() {
        if (!root.workspacesData || root.workspacesData.length === 0) return
        var now = Date.now()
        var modified = false
        var copy = JSON.parse(JSON.stringify(root.workspacesData))
        copy.forEach(function(ws) {
            (ws.tasks || []).forEach(function(t) {
                if (!t.reminder) return
                var ts = new Date(t.reminder).getTime()
                if (isNaN(ts) || ts > now) return
                var reminderDt = Qt.formatDateTime(new Date(t.reminder), "ddd, d MMM yyyy  HH:mm")
                var body = reminderDt + (t.description ? "\n" + t.description : "")
                root.sendReminderNotification(i18n("Reminder: %1", t.title), body)
                t.reminder = ""
                t.lastModified = new Date().toISOString()  // mark local as newer than Google post-PATCH
                modified = true
            })
        })
        if (modified) {
            root.workspacesData = copy
            plasmoid.configuration.tasks = JSON.stringify(copy)
            root.reloadTaskModel()
            if (plasmoid.configuration.googleEnabled
                    && plasmoid.configuration.googleAutoSync
                    && !googleSync.isSyncing)
                googleSync.schedulePush()
        }
    }

    // ─── Context menu (right-click on tray) ──────────────────────────────────
    Component.onCompleted: {
        loadTasks()

        if (plasmoid.configuration.googleEnabled && plasmoid.configuration.googleAutoSync)
            Qt.callLater(function() { googleSync.sync() })

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
        // Config page bumps this counter when a workspace is assigned to a
        // Google Tasks list, so we reload the local state and run a full sync.
        function onGoogleSyncRequestVersionChanged() {
            if (!plasmoid.configuration.googleEnabled) return
            root.loadTasks()
            Qt.callLater(function() {
                if (!googleSync.isSyncing) googleSync.sync()
            })
        }
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

    // ─── Reminder checker ─────────────────────────────────────────────────────
    Timer {
        id: reminderChecker
        interval: 30000   // check every 30 s → max 30 s delay on notifications
        repeat: true
        running: true
        onTriggered: root.checkReminders()
    }

    // ─── Task model ───────────────────────────────────────────────────────────
    ListModel { id: taskModel }

    TextMetrics {
        id: popupTextMetrics
    }

    // ─── Google Tasks sync ────────────────────────────────────────────────────
    GoogleTasksSync {
        id: googleSync
        onSyncComplete: function(success, _msg) {
            if (!success) return

            // Merge sync result into current workspacesData without overwriting
            // any task additions/deletions/workspace changes made during the
            // async sync operation.
            var syncedData = googleSync._lastSyncData
            if (Array.isArray(syncedData) && syncedData.length > 0) {
                var cur = JSON.parse(JSON.stringify(root.workspacesData))

                syncedData.forEach(function(syncedWs, i) {
                    if (!cur[i]) return

                    if (!syncedWs.googleTaskListId) return  // non-synced ws: keep cur as-is

                    cur[i].googleSyncedIds  = syncedWs.googleSyncedIds
                    cur[i].googleTaskListId = syncedWs.googleTaskListId

                    var syncedByUid = {}
                    ;(syncedWs.tasks || []).forEach(function(t) { if (t.uid) syncedByUid[t.uid] = t })
                    var curByUid = {}
                    ;(cur[i].tasks || []).forEach(function(t) { if (t.uid) curByUid[t.uid] = t })

                    var result = []

                    // Process tasks present in current state
                    ;(cur[i].tasks || []).forEach(function(t) {
                        if (!t.uid) { result.push(t); return }
                        var s = syncedByUid[t.uid]
                        if (!s) {
                            // Not in sync result — remote-deleted if id was known & gone
                            if (t.googleTaskId
                                    && cur[i].googleSyncedIds.indexOf(t.googleTaskId) < 0) {
                                return  // remote-deleted: drop
                            }
                            result.push(t)  // added after sync started or local-only: keep
                            return
                        }
                        // Apply googleTaskId + remote-updated content
                        var m = JSON.parse(JSON.stringify(t))
                        if (s.googleTaskId) m.googleTaskId = s.googleTaskId
                        if (s.lastModified > (t.lastModified || "")) {
                            m.title = s.title; m.description = s.description
                            m.done  = s.done;  m.lastModified = s.lastModified
                            if (s.reminder !== undefined) m.reminder = s.reminder
                        }
                        result.push(m)
                    })

                    // Add tasks pulled from Google that don't exist locally
                    ;(syncedWs.tasks || []).forEach(function(t) {
                        if (t.uid && !curByUid[t.uid]) result.push(t)
                    })

                    cur[i].tasks = result
                })

                // Preserve workspaces added during sync (beyond sync snapshot)
                for (var j = syncedData.length; j < root.workspacesData.length; j++)
                    if (!cur[j]) cur.push(root.workspacesData[j])

                root.workspacesData = cur
                plasmoid.configuration.tasks = JSON.stringify(cur)
            }

            if (root.activeEdits > 0) root._pendingSyncReload = true
            else root.loadTasks()
        }
    }

    function generateUid() {
        try { if (typeof Qt.uuidv4 === "function") return Qt.uuidv4() } catch(e) {}
        return "xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0
            return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
        })
    }

    function measurePopupTextWidth(text, bold, pixelSize) {
        popupTextMetrics.font.bold = !!bold
        popupTextMetrics.font.pixelSize = pixelSize || Kirigami.Theme.defaultFont.pixelSize
        popupTextMetrics.text = (text && text.length > 0) ? text : " "
        return popupTextMetrics.advanceWidth
    }

    function estimateWorkspacePopupWidth(ws) {
        var maxTaskTitleWidth = 0
        ;(ws.tasks || []).forEach(function(t) {
            maxTaskTitleWidth = Math.max(
                maxTaskTitleWidth,
                root.measurePopupTextWidth(t.title || "", false, Kirigami.Theme.defaultFont.pixelSize)
            )
        })

        var todoSectionMargins = Kirigami.Units.largeSpacing * 2
        var taskRowControls = Kirigami.Units.gridUnit * 10
        var taskRowPadding = Kirigami.Units.gridUnit * 2
        var taskRowWidth = todoSectionMargins + taskRowControls + taskRowPadding + maxTaskTitleWidth

        var headerWidth = todoSectionMargins
                        + root.measurePopupTextWidth(i18n("Tasks"), true, Kirigami.Theme.defaultFont.pixelSize)
                        + Kirigami.Units.gridUnit * 10

        var addRowWidth = todoSectionMargins + Kirigami.Units.gridUnit * 18
        return Math.max(root.popupBaseWidth, taskRowWidth, headerWidth, addRowWidth)
    }

    function estimateWorkspaceTaskListHeight(ws) {
        var taskCount = (ws.tasks || []).length
        var taskRowHeight = Kirigami.Units.gridUnit * 2.4
        var taskSpacing = 2
        var verticalPadding = Kirigami.Units.smallSpacing * 2
        return verticalPadding + Math.max(0, taskCount * (taskRowHeight + taskSpacing) - taskSpacing)
    }

    function estimatePopupHeight() {
        var baseSectionsHeight = Kirigami.Units.gridUnit * 22
        var tallestTaskList = Kirigami.Units.gridUnit * 4
        ;(root.workspacesData || []).forEach(function(ws) {
            tallestTaskList = Math.max(tallestTaskList, root.estimateWorkspaceTaskListHeight(ws))
        })
        return Math.max(root.popupBaseHeight, baseSectionsHeight + tallestTaskList)
    }

    function lockPopupBaseWidth() {
        if (root.popupBaseWidthLocked) return

        var widest = Kirigami.Units.gridUnit * 32
        ;(root.workspacesData || []).forEach(function(ws) {
            widest = Math.max(widest, root.estimateWorkspacePopupWidth(ws))
        })

        root.popupBaseWidth = widest
        root.popupBaseWidthLocked = true
    }

    function lockPopupBaseHeight() {
        if (root.popupBaseHeightLocked) return
        root.popupBaseHeight = root.estimatePopupHeight()
        root.popupBaseHeightLocked = true
    }

    function updateDoneCount() {
        var n = 0
        for (var i = 0; i < taskModel.count; i++)
            if (taskModel.get(i).done) n++
        doneCount = n
    }

    // Populate taskModel from workspacesData[currentWorkspace]
    function reloadTaskModel() {
        // Preserve which tasks were expanded so sync doesn't collapse open items
        var expandedUids = {}
        for (var i = 0; i < taskModel.count; i++) {
            var item = taskModel.get(i)
            if (item.expanded && item.uid) expandedUids[item.uid] = true
        }

        taskModel.clear()
        var ws = workspacesData[currentWorkspace]
        if (!ws) return
        ;(ws.tasks || []).forEach(function(t) {
            taskModel.append({
                title:        t.title        || "",
                description:  t.description  || "",
                done:         t.done         || false,
                uid:          t.uid          || "",
                lastModified: t.lastModified || "",
                googleTaskId: t.googleTaskId || "",
                reminder:     t.reminder     || "",
                expanded:     !!(t.uid && expandedUids[t.uid]),
                editDesc:     false
            })
        })
    }

    // Sync taskModel → workspacesData[currentWorkspace] (deep-copy to trigger bindings)
    function syncCurrentWorkspace() {
        if (workspacesData.length === 0) return
        var prevTasks = workspacesData[currentWorkspace].tasks || []
        var prevMap   = {}
        prevTasks.forEach(function(t) { if (t.uid) prevMap[t.uid] = t })

        var now   = new Date().toISOString()
        var tasks = []
        for (var i = 0; i < taskModel.count; i++) {
            var t    = taskModel.get(i)
            var uid  = t.uid || root.generateUid()
            var prev = prevMap[uid]
            var changed = !prev
                || prev.title       !== t.title
                || prev.description !== t.description
                || prev.done        !== t.done
                || (prev.reminder || "") !== (t.reminder || "")
            tasks.push({
                title:        t.title,
                description:  t.description,
                done:         t.done,
                uid:          uid,
                reminder:     t.reminder     || "",
                lastModified: changed ? now : (prev && prev.lastModified || now),
                googleTaskId: t.googleTaskId || (prev && prev.googleTaskId || "")
            })
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

        // Migration: ensure every task has uid + lastModified,
        //            every workspace has googleTaskListId + googleSyncedIds
        var migrated = false
        var now = new Date().toISOString()
        workspacesData = workspacesData.map(function(ws) {
            if (!ws.googleTaskListId) { ws.googleTaskListId = ""; migrated = true }
            if (!ws.googleSyncedIds)  { ws.googleSyncedIds  = []; migrated = true }
            ws.tasks = (ws.tasks || []).map(function(t) {
                if (!t.uid)          { t.uid          = root.generateUid(); migrated = true }
                if (!t.lastModified) { t.lastModified = now;                migrated = true }
                return t
            })
            return ws
        })
        if (migrated) plasmoid.configuration.tasks = JSON.stringify(workspacesData)

        if (currentWorkspace >= workspacesData.length) currentWorkspace = 0
        lockPopupBaseWidth()
        lockPopupBaseHeight()
        reloadTaskModel()
        updateDoneCount()
        Qt.callLater(root.checkReminders)
    }

    function saveTasks() {
        syncCurrentWorkspace()
        plasmoid.configuration.tasks = JSON.stringify(workspacesData)
        updateDoneCount()
        if (plasmoid.configuration.googleEnabled
                && plasmoid.configuration.googleAutoSync
                && !googleSync.isSyncing) {
            googleSync.schedulePush()
        }
    }

    function addTask(title) {
        title = (title || "").trim()
        if (title.length === 0) return false
        var autoExpand = plasmoid.configuration.autoExpandNewTask
        taskModel.append({
            title:        title,
            description:  "",
            done:         false,
            uid:          root.generateUid(),
            lastModified: new Date().toISOString(),
            reminder:     "",
            expanded:     autoExpand,
            editDesc:     autoExpand
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

        // Panel thickness: height on horizontal panels, width on vertical.
        // Plasmoid.formFactor === 3 is Vertical (PlasmaCore.Types.Vertical).
        readonly property int panelThickness: Plasmoid.formFactor === 3
                                              ? compactRoot.width
                                              : compactRoot.height
        readonly property int iconSize: Math.max(
            Kirigami.Units.iconSizes.small,
            Math.min(Kirigami.Units.iconSizes.enormous, panelThickness)
        )
        readonly property int timerPixelSize: Math.max(
            Kirigami.Units.gridUnit * 0.7,
            Math.round(panelThickness * 0.45)
        )
        readonly property int dotSize: Math.max(4, Math.round(panelThickness * 0.12))

        TextMetrics {
            id: timerMetrics
            font.pixelSize: compactRoot.timerPixelSize
            font.bold: true
            text: "00:00"
        }

        readonly property real _pad:   Kirigami.Units.smallSpacing * 2
        readonly property real _icon:  iconSize
        readonly property real _dot:   dotSize + Kirigami.Units.smallSpacing / 2
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
                Layout.preferredWidth:  compactRoot.iconSize
                Layout.preferredHeight: compactRoot.iconSize
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                visible: compactRoot.showTimer && compactRoot.showIcon
                width: compactRoot.dotSize
                height: compactRoot.dotSize
                radius: width / 2
                color: root.modeColor()
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                visible: compactRoot.showTimer
                text: root.formatTime(root.remainingSeconds)
                color: root.modeColor()
                font.bold: true
                font.pixelSize: compactRoot.timerPixelSize
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // ─── Full representation (popup) ─────────────────────────────────────────
    fullRepresentation: ColumnLayout {
        id: fullRep
        implicitWidth: root.popupBaseWidth
        implicitHeight: root.popupBaseHeight
        Layout.minimumWidth: root.popupBaseWidth
        Layout.preferredWidth: root.popupBaseWidth
        Layout.minimumHeight: root.popupBaseHeight
        Layout.preferredHeight: root.popupBaseHeight
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
            Layout.preferredHeight: implicitHeight
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
            Layout.fillHeight: true
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

                PlasmaComponents3.ToolButton {
                    id: syncBtn
                    visible: plasmoid.configuration.googleEnabled
                    flat: true
                    icon.name: googleSync.syncStatus === "error" ? "dialog-error" : "view-refresh"
                    onClicked: googleSync.sync()
                    QQC2.ToolTip.text: googleSync.syncMessage.length > 0
                                       ? googleSync.syncMessage
                                       : i18n("Sync with Google Tasks")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 600

                    SequentialAnimation {
                        running: googleSync.isSyncing
                        loops: Animation.Infinite
                        NumberAnimation { target: syncBtn; property: "opacity"; to: 0.3; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { target: syncBtn; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                        onRunningChanged: if (!running) syncBtn.opacity = 1.0
                    }
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
                        readonly property real uniformTabWidth: {
                            var widest = 0
                            for (var i = 0; i < tabWidthRepeater.count; i++) {
                                widest = Math.max(widest, tabWidthRepeater.itemAt(i).requiredWidth)
                            }
                            return widest
                        }

                        Repeater {
                            id: tabWidthRepeater
                            model: root.workspacesData.length

                            Item {
                                readonly property real requiredWidth:
                                    Math.max(tabWidthMetrics.advanceWidth, boldTabWidthMetrics.advanceWidth)
                                    + Kirigami.Units.smallSpacing * 2

                                TextMetrics {
                                    id: tabWidthMetrics
                                    font.family: Kirigami.Theme.defaultFont.family
                                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                                    font.italic: Kirigami.Theme.defaultFont.italic
                                    text: root.workspacesData[index]
                                          ? root.workspacesData[index].name : ""
                                }

                                TextMetrics {
                                    id: boldTabWidthMetrics
                                    font.family: Kirigami.Theme.defaultFont.family
                                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                                    font.italic: Kirigami.Theme.defaultFont.italic
                                    font.weight: Font.Bold
                                    text: root.workspacesData[index]
                                          ? root.workspacesData[index].name : ""
                                }
                            }
                        }

                        Repeater {
                            model: root.workspacesData.length

                            delegate: Item {
                                id: wsTabDelegate
                                readonly property bool isActive: index === root.currentWorkspace
                                property bool editingName: false
                                readonly property real reservedLabelWidth:
                                    Math.max(tabLabelMetrics.advanceWidth, tabLabelBoldMetrics.advanceWidth)
                                readonly property color tabBorderColor:
                                    Qt.rgba(Kirigami.Theme.textColor.r,
                                            Kirigami.Theme.textColor.g,
                                            Kirigami.Theme.textColor.b, 0.22)
                                readonly property color tabFillColor:
                                    wsTabDelegate.isActive
                                        ? Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                                  Kirigami.Theme.backgroundColor.g,
                                                  Kirigami.Theme.backgroundColor.b, 0.16)
                                        : Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                                  Kirigami.Theme.backgroundColor.g,
                                                  Kirigami.Theme.backgroundColor.b, 0.06)

                                // Fixed height across all tabs so the Row stays on one line
                                implicitHeight: Kirigami.Units.iconSizes.small
                                                + Kirigami.Units.smallSpacing * 4
                                implicitWidth:  wsTabRow.uniformTabWidth

                                TextMetrics {
                                    id: tabLabelMetrics
                                    font.family: tabLabel.font.family
                                    font.pixelSize: tabLabel.font.pixelSize
                                    font.weight: tabLabel.font.weight
                                    font.italic: tabLabel.font.italic
                                    text: root.workspacesData[index]
                                          ? root.workspacesData[index].name : ""
                                }

                                TextMetrics {
                                    id: tabLabelBoldMetrics
                                    font.family: tabLabel.font.family
                                    font.pixelSize: tabLabel.font.pixelSize
                                    font.italic: tabLabel.font.italic
                                    font.weight: Font.Bold
                                    text: root.workspacesData[index]
                                          ? root.workspacesData[index].name : ""
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.bottomMargin: wsTabDelegate.isActive ? 0 : 1
                                    radius: 3
                                    color: wsTabDelegate.tabFillColor
                                    border.width: 1
                                    border.color: wsTabDelegate.isActive
                                                  ? Kirigami.Theme.highlightColor
                                                  : wsTabDelegate.tabBorderColor
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: wsTabDelegate.isActive
                                           ? Kirigami.Theme.backgroundColor
                                           : "transparent"
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 2
                                    visible: wsTabDelegate.isActive
                                    color: Kirigami.Theme.highlightColor
                                }

                                RowLayout {
                                    id: tabInner
                                    anchors.centerIn: parent
                                    spacing: 0

                                    // Workspace name label
                                    PlasmaComponents3.Label {
                                        id: tabLabel
                                        visible: !wsTabDelegate.editingName
                                        Layout.preferredWidth: wsTabDelegate.reservedLabelWidth
                                        text: root.workspacesData[index]
                                              ? root.workspacesData[index].name : ""
                                        color: wsTabDelegate.isActive
                                               ? Kirigami.Theme.highlightColor
                                               : Kirigami.Theme.textColor
                                        font.bold: wsTabDelegate.isActive
                                        opacity: wsTabDelegate.isActive ? 1.0 : 0.9
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
                                }

                                QQC2.Menu {
                                    id: wsTabContextMenu

                                    QQC2.MenuItem {
                                        text: i18n("Rename workspace")
                                        onTriggered: {
                                            if (!wsTabDelegate.isActive)
                                                root.switchWorkspace(index)
                                            wsTabDelegate.editingName = true
                                            Qt.callLater(function() {
                                                wsNameField.forceActiveFocus()
                                                wsNameField.selectAll()
                                            })
                                        }
                                    }

                                    QQC2.MenuItem {
                                        text: i18n("Delete workspace")
                                        enabled: root.workspacesData.length > 1
                                        onTriggered: {
                                            if (!wsTabDelegate.isActive)
                                                root.switchWorkspace(index)
                                            deleteWsDialog.open()
                                        }
                                    }
                                }

                                TapHandler {
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: function(eventPoint, button) {
                                        if (button === Qt.RightButton) {
                                            wsTabContextMenu.popup()
                                            return
                                        }
                                        if (!wsTabDelegate.isActive)
                                            root.switchWorkspace(index)
                                    }
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
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 4
                Layout.preferredHeight: Math.max(
                    Kirigami.Units.gridUnit * 4,
                    root.popupBaseHeight
                    - (Kirigami.Units.gridUnit * 22)
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
                        taskReminder:    model.reminder || ""

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
                        onReminderSet: function(isoDatetime) {
                            taskModel.setProperty(index, "reminder", isoDatetime)
                            root.saveTasks()
                        }
                        onEditingStarted: root.activeEdits++
                        onEditingEnded:   root.activeEdits = Math.max(0, root.activeEdits - 1)
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
