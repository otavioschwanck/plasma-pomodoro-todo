import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: configPage

    property bool   cfg_googleEnabled:      plasmoid.configuration.googleEnabled
    property string cfg_googleClientId:     plasmoid.configuration.googleClientId
    property string cfg_googleAccountEmail: plasmoid.configuration.googleAccountEmail
    property bool   cfg_googleAutoSync:     plasmoid.configuration.googleAutoSync
    property int    cfg_googleSyncInterval: plasmoid.configuration.googleSyncInterval
    property int    cfg_googleAuthVersion:  plasmoid.configuration.googleAuthVersion

    property string clientSecretInput: ""
    property bool   hasRefreshToken:   false
    property bool   isAuthenticating:  false
    property string authError:         ""
    property string _sessionToken:     ""
    readonly property bool isConnected: hasRefreshToken

    implicitHeight: form.implicitHeight + Kirigami.Units.largeSpacing * 2

    WalletHelper { id: configWallet }

    GoogleTasksSync {
        id: configGoogleSync
        allowAutoSync: false
        onSyncComplete: {}
    }

    Component.onCompleted: {
        console.log("[pomodoro] ConfigGoogle: opened, checking KWallet for refresh token")
        configWallet.hasEntry("google-refresh-token", function(has) {
            console.log("[pomodoro] ConfigGoogle: has refresh token in KWallet: " + has)
            configPage.hasRefreshToken = has
            if (has) {
                configGoogleSync._withToken(function(token) {
                    if (token) {
                        console.log("[pomodoro] ConfigGoogle: session token obtained ok")
                        configPage._sessionToken = token
                        _loadTaskLists(token)
                    } else {
                        console.log("[pomodoro] ConfigGoogle: _withToken returned empty (KWallet locked or refresh failed)")
                    }
                })
            }
        })
    }

    // ── OAuth2 Browser Flow (PKCE — Tasks API requires this) ─────────────────
    function startAuth() {
        var id = (configPage.cfg_googleClientId || "").trim()
        configPage.cfg_googleClientId = id
        plasmoid.configuration.googleClientId = id
        if (!id)                           { configPage.authError = i18n("Enter Client ID first.");     return }
        if (!configPage.clientSecretInput) { configPage.authError = i18n("Enter Client Secret first."); return }

        configPage.authError        = ""
        configPage.isAuthenticating = true

        console.log("[pomodoro] startAuth: launching OAuth browser flow, clientId=" + id.substring(0, 12) + "...")
        configWallet.googleAuth(id, configPage.clientSecretInput, function(json) {
            configPage.isAuthenticating = false
            var d = {}
            try { d = JSON.parse(json) } catch(e) {
                console.log("[pomodoro] startAuth: failed to parse response JSON: " + json.substring(0, 100))
            }

            if (d.error) {
                console.log("[pomodoro] startAuth: OAuth error: " + d.error + " " + (d.error_description || ""))
                configPage.authError = d.error + (d.error_description ? ": " + d.error_description : "")
                return
            }
            if (!d.access_token) {
                console.log("[pomodoro] startAuth: no access_token in response, keys=" + Object.keys(d).join(","))
                configPage.authError = i18n("No token received — check credentials and try again")
                return
            }

            console.log("[pomodoro] startAuth: access token received, has_refresh=" + !!d.refresh_token + " expires_in=" + d.expires_in)
            configWallet.writeSecret("google-client-secret", configPage.clientSecretInput)
            if (d.refresh_token)
                configWallet.writeSecret("google-refresh-token", d.refresh_token)
            else
                console.log("[pomodoro] startAuth: WARNING no refresh_token in response (user may need to revoke & reconnect to get one)")
            configWallet.writeSecret("google-access-token", d.access_token)
            plasmoid.configuration.googleTokenExpiry =
                String(Date.now() + (d.expires_in || 3600) * 1000)

            configPage._sessionToken   = d.access_token
            configPage.hasRefreshToken = !!d.refresh_token

            // Fetch account email
            var uxhr = new XMLHttpRequest()
            uxhr.open("GET", "https://www.googleapis.com/oauth2/v2/userinfo")
            uxhr.setRequestHeader("Authorization", "Bearer " + d.access_token)
            uxhr.onreadystatechange = function() {
                if (uxhr.readyState !== XMLHttpRequest.DONE) return
                if (uxhr.status === 200) {
                    var u = JSON.parse(uxhr.responseText)
                    configPage.cfg_googleAccountEmail = u.email || u.name || ""
                    plasmoid.configuration.googleAccountEmail = configPage.cfg_googleAccountEmail
                }
            }
            uxhr.send()

            configPage.cfg_googleAuthVersion++
            plasmoid.configuration.googleAuthVersion = configPage.cfg_googleAuthVersion
            _loadTaskLists(d.access_token)
        })
    }

    // ── Task list model + picker ─────────────────────────────────────────────
    ListModel { id: taskListModel }

    QQC2.Dialog {
        id: taskListPicker
        title: i18n("Choose Task List")
        modal: true
        width: Math.min(configPage.width * 0.9, Kirigami.Units.gridUnit * 28)
        x: Math.round((configPage.width  - width)  / 2)
        y: Math.round((configPage.height - height) / 2)

        property int    wsIndex:   -1
        property bool   _loading:  false
        property string _errorMsg: ""

        onAboutToShow: {
            taskListModel.clear()
            _errorMsg = ""
            _loading  = true

            function doLoad(t) {
                if (!t) {
                    _loading  = false
                    _errorMsg = i18n("Could not get an access token. Try disconnecting and reconnecting your account.")
                    return
                }
                configPage._sessionToken = t
                configGoogleSync.listTaskLists(t, function(ok, lists, errCode) {
                    _loading = false
                    console.log("[pomodoro] listTaskLists result: ok=" + ok + " count=" + (ok ? lists.length : 0) + " errCode=" + (errCode || "none"))
                    if (ok) {
                        lists.forEach(function(l) {
                            taskListModel.append({listId: l.id, title: l.title})
                        })
                    } else if (errCode === "tasks_api_disabled") {
                        _errorMsg = i18n("Google Tasks API is not enabled in your Google Cloud project. Go to Google Cloud Console → APIs & Services and enable the Tasks API, then try again.")
                    } else {
                        _errorMsg = i18n("Could not load task lists. Check your connection and try again.")
                    }
                })
            }

            // Prefer the already-validated session token to avoid a redundant
            // KWallet round-trip that may fail if the wallet is locked.
            if (configPage._sessionToken) {
                console.log("[pomodoro] taskListPicker: using cached session token")
                doLoad(configPage._sessionToken)
            } else {
                console.log("[pomodoro] taskListPicker: no session token, calling _withToken")
                configGoogleSync._withToken(doLoad)
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: taskListPicker._loading
                running: taskListPicker._loading
            }

            QQC2.Label {
                visible: !taskListPicker._loading && taskListPicker._errorMsg !== ""
                Layout.fillWidth: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                text: taskListPicker._errorMsg
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
            }

            QQC2.Label {
                visible: !taskListPicker._loading && taskListPicker._errorMsg === "" && taskListModel.count === 0
                Layout.fillWidth: true
                text: i18n("No task lists found.")
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.6
            }

            Repeater {
                model: taskListModel
                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    text: model.title
                    onClicked: {
                        _applyTaskList(taskListPicker.wsIndex, model.listId)
                        taskListPicker.close()
                    }
                }
            }
        }
        footer: QQC2.DialogButtonBox {
            QQC2.Button {
                text: i18n("Cancel")
                QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                onClicked: taskListPicker.close()
            }
        }
    }

    function _applyTaskList(wsIdx, listId) {
        var data = []
        try { data = JSON.parse(plasmoid.configuration.tasks) } catch(e) {}
        if (wsIdx >= 0 && wsIdx < data.length) {
            var prev = data[wsIdx].googleTaskListId || ""
            data[wsIdx].googleTaskListId = listId
            plasmoid.configuration.tasks = JSON.stringify(data)
            // When a list is (re)assigned, ask main.qml to run a full sync
            // so local tasks are pushed and remote tasks pulled immediately.
            if (listId && listId !== prev) {
                plasmoid.configuration.googleSyncRequestVersion =
                    (plasmoid.configuration.googleSyncRequestVersion || 0) + 1
            }
        }
    }

    function _loadTaskLists(token, callback) {
        configGoogleSync.listTaskLists(token, function(ok, lists) {
            taskListModel.clear()
            if (ok) lists.forEach(function(l) {
                taskListModel.append({listId: l.id, title: l.title})
            })
            if (callback) callback()
        })
    }

    function _chooseTaskList(wsIdx) {
        taskListPicker.wsIndex = wsIdx
        taskListPicker.open()
    }

    function disconnectAccount() {
        configWallet.clearSecret("google-refresh-token")
        configWallet.clearSecret("google-client-secret")
        configWallet.clearSecret("google-access-token")
        configPage.hasRefreshToken = false
        configPage._sessionToken = ""
        configPage.cfg_googleAccountEmail = ""
        plasmoid.configuration.googleAccountEmail = ""
        configPage.cfg_googleAuthVersion++
        plasmoid.configuration.googleAuthVersion = configPage.cfg_googleAuthVersion
        taskListModel.clear()
    }

    // ── Form ─────────────────────────────────────────────────────────────────
    Kirigami.FormLayout {
        id: form
        anchors { top: parent.top; left: parent.left; right: parent.right
                  margins: Kirigami.Units.largeSpacing }

        // ── Master toggle ─────────────────────────────────────────────────
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Google Tasks:")
            text: i18n("Enable Google Tasks sync")
            checked: cfg_googleEnabled
            onToggled: cfg_googleEnabled = checked
        }

        // ── Account ───────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Google Account")
        }

        // Connected state
        RowLayout {
            visible: configPage.isConnected
            Kirigami.FormData.label: ""
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon { source: "user-online"; implicitWidth: Kirigami.Units.iconSizes.small; implicitHeight: implicitWidth }
            QQC2.Label { text: configPage.cfg_googleAccountEmail || i18n("Connected"); font.bold: true }
            Item { implicitWidth: Kirigami.Units.gridUnit }
            QQC2.Button { text: i18n("Disconnect"); onClicked: configPage.disconnectAccount() }
        }

        // Not connected: credentials
        QQC2.TextField {
            visible: !configPage.isConnected
            Kirigami.FormData.label: i18n("Client ID:")
            placeholderText: i18n("OAuth2 Client ID")
            text: cfg_googleClientId
            onEditingFinished: {
                cfg_googleClientId = text.trim()
                plasmoid.configuration.googleClientId = cfg_googleClientId
            }
            implicitWidth: Kirigami.Units.gridUnit * 22
        }

        QQC2.TextField {
            visible: !configPage.isConnected
            Kirigami.FormData.label: i18n("Client Secret:")
            placeholderText: i18n("OAuth2 Client Secret")
            echoMode: TextInput.Password
            text: configPage.clientSecretInput
            onEditingFinished: configPage.clientSecretInput = text
            implicitWidth: Kirigami.Units.gridUnit * 22
        }

        QQC2.Label {
            visible: !configPage.isConnected
            Kirigami.FormData.label: ""
            text: i18n("In Google Cloud Console, enable the Tasks API and create an OAuth Client ID with type \"Desktop app\".")
            wrapMode: Text.WordWrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }

        QQC2.Button {
            visible: !configPage.isConnected
            Kirigami.FormData.label: ""
            text: i18n("Open Google Cloud Console →")
            icon.name: "internet-web-browser"
            onClicked: Qt.openUrlExternally("https://console.cloud.google.com/apis/credentials")
        }

        QQC2.Label {
            visible: !configPage.isConnected && configPage.authError !== ""
            Kirigami.FormData.label: ""
            text: configPage.authError
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }

        RowLayout {
            visible: !configPage.isConnected
            Kirigami.FormData.label: ""
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: configPage.isAuthenticating
                      ? i18n("Waiting for browser…")
                      : i18n("Connect Google Account")
                icon.name: "user-online"
                enabled: !configPage.isAuthenticating &&
                         cfg_googleClientId !== "" &&
                         configPage.clientSecretInput !== ""
                onClicked: configPage.startAuth()
            }

            QQC2.BusyIndicator {
                visible: configPage.isAuthenticating
                running: configPage.isAuthenticating
                implicitWidth:  Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                padding: 0
            }
        }

        QQC2.Label {
            visible: configPage.isAuthenticating
            Kirigami.FormData.label: ""
            text: i18n("Complete authorization in the browser that just opened.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        }

        // ── Workspace → Task list mapping ─────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Workspace Task Lists")
            enabled: cfg_googleEnabled
        }

        Repeater {
            model: (function() {
                var d = []; try { d = JSON.parse(plasmoid.configuration.tasks) } catch(e) {}
                return d.length
            })()

            delegate: RowLayout {
                Kirigami.FormData.label: (function() {
                    var d = []; try { d = JSON.parse(plasmoid.configuration.tasks) } catch(e) {}
                    return d[index] ? (d[index].name || "") : ""
                })()
                enabled: cfg_googleEnabled && configPage.isConnected
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: (function() {
                        var d = []; try { d = JSON.parse(plasmoid.configuration.tasks) } catch(e) {}
                        var lid = d[index] ? (d[index].googleTaskListId || "") : ""
                        if (!lid) return i18n("(not assigned)")
                        for (var i = 0; i < taskListModel.count; i++)
                            if (taskListModel.get(i).listId === lid) return taskListModel.get(i).title
                        return lid
                    })()
                    opacity: 0.8
                }

                QQC2.Button {
                    text: i18n("Choose…")
                    icon.name: "view-list-text"
                    onClicked: configPage._chooseTaskList(index)
                }

                QQC2.Button {
                    icon.name: "edit-clear"
                    visible: (function() {
                        var d = []; try { d = JSON.parse(plasmoid.configuration.tasks) } catch(e) {}
                        return d[index] ? !!d[index].googleTaskListId : false
                    })()
                    onClicked: _applyTaskList(index, "")
                    QQC2.ToolTip.text: i18n("Remove assignment"); QQC2.ToolTip.visible: hovered
                }
            }
        }

        // ── Sync behaviour ────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Sync Behaviour")
            enabled: cfg_googleEnabled
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Auto-sync on save:")
            text: i18n("Sync automatically when tasks are added or changed")
            enabled: cfg_googleEnabled
            checked: cfg_googleAutoSync
            onToggled: cfg_googleAutoSync = checked
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Periodic sync (minutes):")
            enabled: cfg_googleEnabled
            from: 0; to: 1440
            value: cfg_googleSyncInterval
            onValueModified: cfg_googleSyncInterval = value
            textFromValue: function(v) { return v === 0 ? i18n("Disabled") : i18np("%1 min", "%1 min", v) }
        }
    }
}
