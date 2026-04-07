# SKILL.md — Knowledge Map for Contributors

A guide to the technologies and patterns used in this project.

---

## 1. QML Basics

QML is Qt's declarative UI language. Key concepts you'll use here:

- **Property bindings** — `width: parent.width * 0.5` re-evaluates automatically when `parent.width` changes
- **Signal handlers** — `onClicked: { ... }`, `onTextChanged: { ... }`
- **`id:` references** — unique within a component file; `root.someFunc()` calls a function on the item with `id: root`
- **`Component.onCompleted`** — runs once after the item is fully constructed
- **Scope chain** — child items can access parent IDs and functions; always use explicit `root.` prefix when calling from sub-components
- **`ListModel` / `ListView`** — Qt's built-in model/view for dynamic lists; use `setProperty(index, "key", value)` to update items in place

Useful docs: [Qt QML reference](https://doc.qt.io/qt-6/qtqml-index.html)

---

## 2. KDE Plasma Plasmoid Structure

A plasmoid is a directory with this layout:

```
widget-id/
├── metadata.json          # Plugin ID, name, author, license
├── contents/
│   ├── config/
│   │   ├── main.xml       # KConfigXT schema → generates plasmoid.configuration.*
│   │   └── config.qml     # Lists config dialog pages
│   └── ui/
│       └── main.qml       # Root: PlasmoidItem { ... }
```

**`PlasmoidItem`** is the root type (from `import org.kde.plasma.plasmoid`). It has:
- `compactRepresentation` — shown in the panel bar
- `fullRepresentation` — shown in the popup when clicked
- `expanded` — toggle to open/close the popup

**Context menu actions:**
```qml
Component.onCompleted: plasmoid.setAction("myAction", "Label", "icon-name")
function action_myAction() { /* handler */ }
```

Install path: `~/.local/share/plasma/plasmoids/<widget-id>/`

---

## 3. Kirigami

Kirigami (`import org.kde.kirigami as Kirigami`) is KDE's adaptive UI framework built on top of QtQuick Controls:

| Component | Use |
|-----------|-----|
| `Kirigami.Icon` | Theme-aware icon (accepts icon name string) |
| `Kirigami.Separator` | Horizontal divider; `FormData.isSection: true` makes it a section header in FormLayout |
| `Kirigami.FormLayout` | Labeled form rows; children use `Kirigami.FormData.label: "..."` |
| `Kirigami.Units.*` | Spacing constants (`smallSpacing`, `largeSpacing`, `gridUnit`, `iconSizes.*`) |
| `Kirigami.Theme.*` | Theme colors (`textColor`, `backgroundColor`, `negativeTextColor`, etc.) |

---

## 4. KDE Plasma Components

`import org.kde.plasma.components as PlasmaComponents3` provides theme-integrated versions of standard controls:

- `PlasmaComponents3.Button` / `ToolButton`
- `PlasmaComponents3.Label`
- `PlasmaComponents3.TextField` / `TextArea`
- `PlasmaComponents3.CheckBox`

Prefer these over bare QtQuick Controls (`QQC2.*`) for anything visible in the widget popup or panel.

---

## 5. KDE Configuration System (KConfigXT)

`contents/config/main.xml` declares config keys with types and defaults:

```xml
<entry name="pomodoroMinutes" type="Int">
  <default>25</default>
</entry>
```

Access in QML: `plasmoid.configuration.pomodoroMinutes`

Config page (`ConfigTimer.qml`): declare `property int cfg_pomodoroMinutes: plasmoid.configuration.pomodoroMinutes` — the `cfg_` prefix is magic: Plasma auto-saves it when the config dialog is accepted.

---

## 6. KDE i18n (Translations)

QML has `i18n()` and `i18np()` as global functions when running inside a plasmoid:

```qml
i18n("Hello")                          // simple string
i18n("Hello %1", userName)             // with substitution
i18np("One task", "%1 tasks", count)   // singular/plural
```

Translation files: `contents/locale/<lang>/LC_MESSAGES/plasma_applet_<id>.po`  
Compile: `msgfmt -o file.mo file.po` (or just run `./install.sh`)

---

## 7. Icon Picker

`import org.kde.iconthemes as KIconThemes` — provides `KIconThemes.IconDialog`, the standard KDE icon chooser:

```qml
KIconThemes.IconDialog {
    id: iconDialog
    onIconNameChanged: iconName => { if (iconName) doSomething(iconName) }
}
// open it:
iconDialog.open()
```

---

## 8. Notifications

`import org.kde.notification` — provides `Notification`:

```qml
Notification {
    id: notif
    componentName: "plasma_workspace"
    eventId: "notification"
    title: "Title"
    text:  "Body"
    urgency: Notification.NormalUrgency
}
notif.sendEvent()
```

**Note:** `PlasmaCore.DataSource` with engine `"executable"` was removed in Plasma 6. Do not use it.

---

## 9. TextMetrics

Used to measure text dimensions without rendering:

```qml
TextMetrics {
    id: tm
    font.pixelSize: 14
    font.bold: true
    text: "00:00"
}
// tm.advanceWidth → pixel width of the text
```

Useful for computing widget sizes before layout is complete.
