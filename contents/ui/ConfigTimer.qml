import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes
import org.kde.kquickcontrols as KQC

Item {
    id: configPage

    property int    cfg_pomodoroMinutes:      plasmoid.configuration.pomodoroMinutes
    property int    cfg_shortBreakMinutes:    plasmoid.configuration.shortBreakMinutes
    property int    cfg_longBreakMinutes:     plasmoid.configuration.longBreakMinutes
    property string cfg_focusColor:           plasmoid.configuration.focusColor
    property string cfg_breakColor:           plasmoid.configuration.breakColor
    property string cfg_trayDisplayMode:      plasmoid.configuration.trayDisplayMode
    property bool   cfg_notificationsEnabled: plasmoid.configuration.notificationsEnabled
    property string cfg_focusIcon:            plasmoid.configuration.focusIcon
    property string cfg_pausedIcon:           plasmoid.configuration.pausedIcon
    property string cfg_shortBreakIcon:       plasmoid.configuration.shortBreakIcon
    property string cfg_longBreakIcon:        plasmoid.configuration.longBreakIcon

    implicitHeight: form.implicitHeight + Kirigami.Units.largeSpacing * 2

    // Single dialog reused for all icon pickers; `target` tracks which cfg to update
    KIconThemes.IconDialog {
        id: iconDialog
        property string target: ""
        onIconNameChanged: iconName => {
            if (!iconName) return
            switch (target) {
                case "focus":      cfg_focusIcon      = iconName; break
                case "paused":     cfg_pausedIcon     = iconName; break
                case "shortBreak": cfg_shortBreakIcon = iconName; break
                case "longBreak":  cfg_longBreakIcon  = iconName; break
            }
        }
    }

    // Reusable inline component for one icon-picker row
    component IconPickerRow: RowLayout {
        property string label: ""
        property string iconName: ""
        property string targetKey: ""

        Kirigami.FormData.label: label
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: iconName || "appointment-new"
            Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }

        QQC2.Label {
            text: iconName || "appointment-new"
            opacity: 0.7
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        QQC2.Button {
            text: i18n("Choose…")
            icon.name: "document-open"
            onClicked: { iconDialog.target = targetKey; iconDialog.open() }
        }
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
            Kirigami.FormData.label: i18n("Focus duration (minutes):")
            from: 1; to: 120
            value: cfg_pomodoroMinutes
            onValueModified: cfg_pomodoroMinutes = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Short break (minutes):")
            from: 1; to: 60
            value: cfg_shortBreakMinutes
            onValueModified: cfg_shortBreakMinutes = value
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Long break (minutes):")
            from: 1; to: 120
            value: cfg_longBreakMinutes
            onValueModified: cfg_longBreakMinutes = value
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            text: i18n("Long break after every 4 focus sessions.")
            opacity: 0.6
            font.pixelSize: Kirigami.Units.gridUnit * 0.85
        }

        // ── Appearance ────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Appearance")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Focus color:")
            spacing: Kirigami.Units.smallSpacing

            KQC.ColorButton {
                color: cfg_focusColor
                showAlphaChannel: false
                onColorChanged: cfg_focusColor = color.toString()
            }
            QQC2.Label { text: cfg_focusColor; opacity: 0.6; font.pixelSize: Kirigami.Units.gridUnit * 0.85 }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Break color:")
            spacing: Kirigami.Units.smallSpacing

            KQC.ColorButton {
                color: cfg_breakColor
                showAlphaChannel: false
                onColorChanged: cfg_breakColor = color.toString()
            }
            QQC2.Label { text: cfg_breakColor; opacity: 0.6; font.pixelSize: Kirigami.Units.gridUnit * 0.85 }
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Show in panel:")
            model: [
                { text: i18n("Icon + timer when running"), value: "iconAndTimer" },
                { text: i18n("Icon only"),                 value: "iconOnly"     },
                { text: i18n("Timer only when running"),   value: "timerOnly"    }
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

        // ── Tray icons ────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Tray Icons")
        }

        IconPickerRow {
            Kirigami.FormData.label: i18n("Focus:")
            iconName:  cfg_focusIcon
            targetKey: "focus"
        }

        IconPickerRow {
            Kirigami.FormData.label: i18n("Paused / idle:")
            iconName:  cfg_pausedIcon
            targetKey: "paused"
        }

        IconPickerRow {
            Kirigami.FormData.label: i18n("Short break:")
            iconName:  cfg_shortBreakIcon
            targetKey: "shortBreak"
        }

        IconPickerRow {
            Kirigami.FormData.label: i18n("Long break:")
            iconName:  cfg_longBreakIcon
            targetKey: "longBreak"
        }

        // ── Notifications ─────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Notifications")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Notify on timer end:")
            checked: cfg_notificationsEnabled
            onToggled: cfg_notificationsEnabled = checked
            text: i18n("Send desktop notification when timer ends")
        }
    }
}
