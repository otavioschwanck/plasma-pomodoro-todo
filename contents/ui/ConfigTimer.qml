import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes
import org.kde.kquickcontrols as KQC

// cfg_ properties are auto-synced with plasmoid.configuration.*
Item {
    id: configPage

    property int    cfg_pomodoroMinutes:   plasmoid.configuration.pomodoroMinutes
    property int    cfg_shortBreakMinutes: plasmoid.configuration.shortBreakMinutes
    property int    cfg_longBreakMinutes:  plasmoid.configuration.longBreakMinutes
    property string cfg_trayIcon:          plasmoid.configuration.trayIcon
    property string cfg_focusColor:        plasmoid.configuration.focusColor
    property string cfg_breakColor:        plasmoid.configuration.breakColor
    property string cfg_trayDisplayMode:   plasmoid.configuration.trayDisplayMode
    property bool   cfg_notificationsEnabled: plasmoid.configuration.notificationsEnabled

    implicitHeight: form.implicitHeight + Kirigami.Units.largeSpacing * 2

    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: iconName => { if (iconName) cfg_trayIcon = iconName }
    }

    Kirigami.FormLayout {
        id: form
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Kirigami.Units.largeSpacing
        }

        // ── Timer durations ───────────────────────────────────────────────
        QQC2.SpinBox {
            Kirigami.FormData.label: "Focus duration (minutes):"
            from: 1; to: 120
            value: cfg_pomodoroMinutes
            onValueModified: cfg_pomodoroMinutes = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: "Short break (minutes):"
            from: 1; to: 60
            value: cfg_shortBreakMinutes
            onValueModified: cfg_shortBreakMinutes = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: "Long break (minutes):"
            from: 1; to: 120
            value: cfg_longBreakMinutes
            onValueModified: cfg_longBreakMinutes = value
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            text: "Long break after every 4 focus sessions."
            opacity: 0.6
            font.pixelSize: Kirigami.Units.gridUnit * 0.85
        }

        // ── Appearance ────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Appearance"
        }

        // Focus color
        RowLayout {
            Kirigami.FormData.label: "Focus color:"
            spacing: Kirigami.Units.smallSpacing

            KQC.ColorButton {
                color: cfg_focusColor
                showAlphaChannel: false
                onColorChanged: cfg_focusColor = color.toString()
            }

            QQC2.Label {
                text: cfg_focusColor
                opacity: 0.6
                font.pixelSize: Kirigami.Units.gridUnit * 0.85
            }
        }

        // Break color
        RowLayout {
            Kirigami.FormData.label: "Break color:"
            spacing: Kirigami.Units.smallSpacing

            KQC.ColorButton {
                color: cfg_breakColor
                showAlphaChannel: false
                onColorChanged: cfg_breakColor = color.toString()
            }

            QQC2.Label {
                text: cfg_breakColor
                opacity: 0.6
                font.pixelSize: Kirigami.Units.gridUnit * 0.85
            }
        }

        // Tray icon picker
        RowLayout {
            Kirigami.FormData.label: "Tray icon:"
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: cfg_trayIcon || "appointment-new"
                Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }

            QQC2.Label {
                text: cfg_trayIcon || "appointment-new"
                opacity: 0.7
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            QQC2.Button {
                text: "Choose…"
                icon.name: "document-open"
                onClicked: iconDialog.open()
            }
        }

        // Tray display mode
        QQC2.ComboBox {
            Kirigami.FormData.label: "Show in panel:"
            model: [
                { text: "Icon + timer when running", value: "iconAndTimer" },
                { text: "Icon only",                 value: "iconOnly"     },
                { text: "Timer only when running",   value: "timerOnly"    }
            ]
            textRole: "text"
            valueRole: "value"
            currentIndex: {
                var v = cfg_trayDisplayMode
                for (var i = 0; i < model.length; i++)
                    if (model[i].value === v) return i
                return 0
            }
            onActivated: cfg_trayDisplayMode = model[currentIndex].value
        }

        // ── Notifications ─────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Notifications"
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: "Notify on timer end:"
            checked: cfg_notificationsEnabled
            onToggled: cfg_notificationsEnabled = checked
            text: "Send desktop notification when timer ends"
        }
    }
}
