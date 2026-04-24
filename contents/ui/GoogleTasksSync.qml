import QtQuick
import org.kde.plasma.plasmoid

// Google Tasks bidirectional sync engine.
// Uses OAuth2 Device Flow tokens stored in KWallet via WalletHelper.
// All HTTP calls use standard GET/POST/PATCH/DELETE — no WebDAV methods.
Item {
    id: googleRoot
    visible: false

    // ── Public API ──────────────────────────────────────────────────────────
    signal syncComplete(bool success, string message)

    property string syncStatus:   ""   // "" | "syncing" | "ok" | "error"
    property string syncMessage:  ""
    property bool   isSyncing:    false
    property bool   allowAutoSync: true   // set false in config page

    property string _cachedToken:   ""
    property var    _lastSyncData:  null

    // ── KWallet helper ──────────────────────────────────────────────────────
    WalletHelper { id: walletHelper }

    // ── Public functions ────────────────────────────────────────────────────

    function sync() {
        if (isSyncing) return
        if (!plasmoid.configuration.googleEnabled) return

        isSyncing   = true
        syncStatus  = "syncing"
        syncMessage = i18n("Syncing…")

        _withToken(function(token) {
            if (!token) {
                isSyncing   = false
                syncStatus  = "error"
                syncMessage = i18n("Not connected — open Settings › Google Tasks")
                return
            }
            _cachedToken = token
            _doSync()
        })
    }

    function schedulePush() {
        pushDebounce.restart()
    }

    // List available task lists — for config UI use only.
    // callback(ok: bool, lists: [{id, title}])
    function listTaskLists(token, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://tasks.googleapis.com/tasks/v1/users/@me/lists")
        xhr.setRequestHeader("Authorization", "Bearer " + token)
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                var d = {}
                try { d = JSON.parse(xhr.responseText) } catch(e) {}
                callback(true, d.items || [])
            } else {
                var _body = xhr.responseText
                var _msg = ""
                if (_body.indexOf("not been used") >= 0 || _body.indexOf("is disabled") >= 0)
                    _msg = "tasks_api_disabled"
                callback(false, [], _msg)
            }
        }
        xhr.ontimeout = function() { callback(false, [], "timeout") }
        xhr.send()
    }

    // ── Private: token management ───────────────────────────────────────────

    function _withToken(callback) {
        var expiry = parseInt(plasmoid.configuration.googleTokenExpiry || "0")
        var expiresIn = Math.round((expiry - Date.now()) / 1000)
        if (Date.now() < expiry - 60000) {
            console.log("[pomodoro] _withToken: cached token still valid (expires in " + expiresIn + "s), reading from KWallet")
            walletHelper.readSecret("google-access-token", function(token) {
                if (token) {
                    console.log("[pomodoro] _withToken: KWallet returned access token ok")
                    callback(token); return
                }
                console.log("[pomodoro] _withToken: KWallet returned empty access token, falling back to refresh")
                _refreshToken(callback)
            })
            return
        }
        console.log("[pomodoro] _withToken: token expired or not set (expiry=" + expiry + "), refreshing")
        _refreshToken(callback)
    }

    function _refreshToken(callback) {
        console.log("[pomodoro] _refreshToken: reading refresh token from KWallet")
        walletHelper.readSecret("google-refresh-token", function(refresh) {
            if (!refresh) {
                console.log("[pomodoro] _refreshToken: no refresh token in KWallet")
                callback(""); return
            }
            console.log("[pomodoro] _refreshToken: refresh token found, reading client secret")
            walletHelper.readSecret("google-client-secret", function(secret) {
                if (!secret) {
                    console.log("[pomodoro] _refreshToken: no client secret in KWallet")
                    callback(""); return
                }
                console.log("[pomodoro] _refreshToken: posting token refresh request")
                var xhr = new XMLHttpRequest()
                xhr.open("POST", "https://oauth2.googleapis.com/token")
                xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
                xhr.timeout = 15000
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE) return
                    var d = {}
                    try { d = JSON.parse(xhr.responseText) } catch(e) {}
                    if (d.access_token) {
                        var exp = Date.now() + (d.expires_in || 3600) * 1000
                        console.log("[pomodoro] _refreshToken: refresh ok, new token expires in " + (d.expires_in || 3600) + "s")
                        walletHelper.writeSecret("google-access-token", d.access_token)
                        plasmoid.configuration.googleTokenExpiry = String(exp)
                        callback(d.access_token)
                    } else {
                        console.log("[pomodoro] _refreshToken: refresh failed HTTP " + xhr.status + " error=" + (d.error || "unknown") + " desc=" + (d.error_description || ""))
                        callback("")
                    }
                }
                xhr.ontimeout = function() {
                    console.log("[pomodoro] _refreshToken: request timed out")
                    callback("")
                }
                xhr.send("client_id="     + encodeURIComponent(plasmoid.configuration.googleClientId) +
                         "&client_secret=" + encodeURIComponent(secret) +
                         "&refresh_token=" + encodeURIComponent(refresh) +
                         "&grant_type=refresh_token")
            })
        })
    }

    // ── Private: sync orchestration ─────────────────────────────────────────

    function _doSync() {
        var data = []
        try { data = JSON.parse(plasmoid.configuration.tasks) } catch(e) {}
        if (!Array.isArray(data)) data = []

        var indices = []
        data.forEach(function(ws, i) { if (ws.googleTaskListId) indices.push(i) })

        if (indices.length === 0) {
            _cachedToken = ""
            isSyncing    = false
            syncStatus   = "error"
            syncMessage  = i18n("No task lists assigned — open Settings › Google Tasks")
            return
        }

        var step = 0
        function next() {
            if (step >= indices.length) {
                // Don't write config here — let main.qml merge with current
                // state to avoid overwriting changes made during async sync.
                googleRoot._lastSyncData = data
                _cachedToken = ""
                isSyncing   = false
                syncStatus  = "ok"
                syncMessage = i18n("Synced")
                syncComplete(true, syncMessage)
                return
            }
            _syncWorkspace(data, indices[step++], function() { next() })
        }
        next()
    }

    function _syncWorkspace(data, wsIndex, callback) {
        var ws = data[wsIndex]
        if (!ws || !ws.googleTaskListId) { callback(); return }

        _listTasks(ws.googleTaskListId, function(ok, remoteTasks) {
            if (!ok) {
                _cachedToken = ""
                isSyncing   = false
                syncStatus  = "error"
                syncMessage = typeof remoteTasks === "string"
                    ? remoteTasks : i18n("Sync failed — check connection")
                callback(); return
            }

            var remoteMap  = {}
            remoteTasks.forEach(function(r) { remoteMap[r.id] = r })

            var localTasks = ws.tasks || []
            var prevSynced = ws.googleSyncedIds || []
            var localById  = {}
            localTasks.forEach(function(t) {
                if (t.googleTaskId) localById[t.googleTaskId] = t
            })

            var updatedTasks = []
            var toPush       = []   // {task, isNew: bool}
            var toDelete     = []   // googleTaskId strings

            // Build remote title index for deduplication
            var remoteByTitle = {}
            Object.keys(remoteMap).forEach(function(rid) {
                var title = (remoteMap[rid].title || "").trim()
                if (title && !remoteByTitle[title]) remoteByTitle[title] = remoteMap[rid]
            })

            // Existing local tasks
            localTasks.forEach(function(t) {
                if (!t.googleTaskId) {
                    // Never synced — check if remote already has a task with the same title
                    // (can happen when sync fires while user is editing, causing duplicates)
                    var titleKey  = (t.title || "").trim()
                    var existing  = titleKey ? remoteByTitle[titleKey] : null
                    // Only link if that remote task isn't already claimed by another local task
                    var alreadyClaimed = existing && !!localById[existing.id]
                    if (existing && !alreadyClaimed) {
                        var linked = JSON.parse(JSON.stringify(t))
                        linked.googleTaskId = existing.id
                        updatedTasks.push(linked)
                    } else {
                        toPush.push({task: t, isNew: true})
                        updatedTasks.push(t)
                    }
                } else if (!remoteMap[t.googleTaskId]) {
                    // Was synced, now missing from remote → remote deleted → drop local
                } else {
                    var r      = remoteMap[t.googleTaskId]
                    var remUpd = r.updated        || ""
                    var locMod = t.lastModified   || ""
                    if (remUpd > locMod) {
                        // Remote newer → pull title/description/done only.
                        // Never touch local reminder: Google Tasks stores only
                        // a date (no time), so round-tripping would clobber the
                        // user's chosen time (e.g. 04:30 becomes 09:00, or is
                        // wiped entirely if the fake 09:00 has already passed).
                        // Reminders are a local-only concern — the user sets
                        // them in the plasmoid and only the plasmoid fires them.
                        var pulled = JSON.parse(JSON.stringify(t))
                        pulled.title        = r.title  || ""
                        pulled.description  = r.notes  || ""
                        pulled.done         = r.status === "completed"
                        pulled.lastModified = remUpd
                        updatedTasks.push(pulled)
                    } else if (locMod > remUpd) {
                        // Local newer → push
                        toPush.push({task: t, isNew: false})
                        updatedTasks.push(t)
                    } else {
                        updatedTasks.push(t)
                    }
                }
            })

            // Remote tasks not in local
            Object.keys(remoteMap).forEach(function(id) {
                if (localById[id]) return  // already handled above
                if (prevSynced.indexOf(id) >= 0) {
                    // Was known but local deleted → delete from Google
                    toDelete.push(id)
                } else {
                    // New from Google → pull
                    var r = remoteMap[id]
                    var newReminder = ""
                    if (r.due) {
                        var nd = new Date(r.due.substring(0, 10) + "T09:00:00")
                        newReminder = nd.toISOString()
                    }
                    updatedTasks.push({
                        title:        r.title  || "",
                        description:  r.notes  || "",
                        done:         r.status === "completed",
                        uid:          _uid(),
                        lastModified: r.updated || new Date().toISOString(),
                        googleTaskId: r.id,
                        reminder:     newReminder
                    })
                }
            })

            ws.tasks           = updatedTasks
            ws.googleSyncedIds = Object.keys(remoteMap).filter(function(id) {
                return toDelete.indexOf(id) < 0
            })

            _executePushes(ws.googleTaskListId, toPush, updatedTasks, function() {
                // Add IDs of newly-pushed tasks — remoteMap was fetched before
                // the push, so newly created tasks would be missing from
                // googleSyncedIds, causing the next sync to re-pull them as
                // "new from Google" and resurrect locally-deleted tasks.
                updatedTasks.forEach(function(t) {
                    if (t.googleTaskId && ws.googleSyncedIds.indexOf(t.googleTaskId) < 0)
                        ws.googleSyncedIds.push(t.googleTaskId)
                })
                _executeDeletes(ws.googleTaskListId, toDelete, function() {
                    callback()
                })
            })
        })
    }

    function _executePushes(listId, ops, updatedTasks, callback) {
        var i = 0
        function next() {
            if (i >= ops.length) { callback(); return }
            var op = ops[i++]
            if (op.isNew) {
                _createTask(listId, op.task, function(ok, newId) {
                    if (ok && newId) {
                        for (var j = 0; j < updatedTasks.length; j++) {
                            if (updatedTasks[j].uid === op.task.uid) {
                                updatedTasks[j].googleTaskId = newId; break
                            }
                        }
                    }
                    next()
                })
            } else {
                _updateTask(listId, op.task.googleTaskId, op.task, function() { next() })
            }
        }
        next()
    }

    function _executeDeletes(listId, ids, callback) {
        var i = 0
        function next() {
            if (i >= ids.length) { callback(); return }
            _deleteTask(listId, ids[i++], function() { next() })
        }
        next()
    }

    // ── Private: Google Tasks API calls ────────────────────────────────────

    function _listTasks(listId, callback) {
        var url = "https://tasks.googleapis.com/tasks/v1/lists/"
                + encodeURIComponent(listId)
                + "/tasks?showCompleted=true&showHidden=true&maxResults=100"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.setRequestHeader("Authorization", "Bearer " + _cachedToken)
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                var d = {}
                try { d = JSON.parse(xhr.responseText) } catch(e) {}
                callback(true, d.items || [])
            } else if (xhr.status === 401) {
                callback(false, i18n("Authentication expired — reconnect in Settings › Google Tasks"))
            } else {
                callback(false, i18n("Error listing tasks (%1)", xhr.status))
            }
        }
        xhr.ontimeout = function() { callback(false, i18n("Network timeout")) }
        xhr.send()
    }

    function _createTask(listId, task, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "https://tasks.googleapis.com/tasks/v1/lists/"
                         + encodeURIComponent(listId) + "/tasks")
        xhr.setRequestHeader("Authorization", "Bearer " + _cachedToken)
        xhr.setRequestHeader("Content-Type",  "application/json")
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var d = {}
            try { d = JSON.parse(xhr.responseText) } catch(e) {}
            callback(xhr.status === 200 || xhr.status === 201, d.id || "")
        }
        xhr.ontimeout = function() { callback(false, "") }
        var body = { title: task.title || "", notes: task.description || "",
                     status: task.done ? "completed" : "needsAction" }
        if (task.reminder) body.due = task.reminder.substring(0, 10) + "T00:00:00.000Z"
        xhr.send(JSON.stringify(body))
    }

    function _updateTask(listId, googleId, task, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("PATCH", "https://tasks.googleapis.com/tasks/v1/lists/"
                          + encodeURIComponent(listId) + "/tasks/"
                          + encodeURIComponent(googleId))
        xhr.setRequestHeader("Authorization", "Bearer " + _cachedToken)
        xhr.setRequestHeader("Content-Type",  "application/json")
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            callback()
        }
        xhr.ontimeout = function() { callback() }
        var body = { id: googleId, title: task.title || "", notes: task.description || "",
                     status: task.done ? "completed" : "needsAction",
                     due: task.reminder
                         ? task.reminder.substring(0, 10) + "T00:00:00.000Z"
                         : null }   // null explicitly clears the due field on Google's side
        xhr.send(JSON.stringify(body))
    }

    function _deleteTask(listId, googleId, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("DELETE", "https://tasks.googleapis.com/tasks/v1/lists/"
                           + encodeURIComponent(listId) + "/tasks/"
                           + encodeURIComponent(googleId))
        xhr.setRequestHeader("Authorization", "Bearer " + _cachedToken)
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            callback()
        }
        xhr.ontimeout = function() { callback() }
        xhr.send()
    }

    function _uid() {
        try { if (typeof Qt.uuidv4 === "function") return Qt.uuidv4() } catch(e) {}
        return "xxxxxxxxxxxx4xxxyxxxxxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0
            return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
        })
    }

    // ── Timers ───────────────────────────────────────────────────────────────

    Timer {
        id: periodicTimer
        interval: Math.max(1, plasmoid.configuration.googleSyncInterval) * 60000
        repeat:   true
        running:  googleRoot.allowAutoSync &&
                  plasmoid.configuration.googleEnabled &&
                  plasmoid.configuration.googleSyncInterval > 0 &&
                  !googleRoot.isSyncing
        onTriggered: googleRoot.sync()
    }

    Timer {
        id: pushDebounce
        interval: 2000
        repeat:   false
        onTriggered: googleRoot.sync()
    }
}
