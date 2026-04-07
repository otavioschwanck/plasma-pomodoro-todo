# CLAUDE.md — Context for AI Assistants

This is a **KDE Plasma 6 plasmoid** (panel widget) written in QML. It combines a Pomodoro timer with a todo list.

## Key Architecture Decisions

### Root scope
`main.qml` is the single root file (`PlasmoidItem`). All runtime state lives here:
- Timer state: `remainingSeconds`, `isRunning`, `sessionCount`, `timerMode`
- Task model: `ListModel { id: taskModel }`
- Functions: `addTask()`, `saveTasks()`, `loadTasks()`, `resetCurrent()`, `resetAll()`, etc.

`fullRepresentation` and `compactRepresentation` are **inline** inside `PlasmoidItem`, so they share its scope. When calling root-level functions from inside representations, **always use the `root.` prefix** (e.g. `root.addTask(text)`) — Plasma may instantiate representations in a slightly different context and bare names can fail to resolve.

### Configuration
All persistent config is declared in `contents/config/main.xml` (KConfigXT schema).  
Access in QML: `plasmoid.configuration.someKey`  
Config page: `contents/ui/ConfigTimer.qml` — properties named `cfg_<key>` are auto-synced.

### Notifications
Uses `org.kde.notification` (`Notification` QML type). **Do not** use `PlasmaCore.DataSource` with engine `"executable"` — that was removed in Plasma 6.

### Panel width (compact representation)
The compact representation computes its own `implicitWidth` using `TextMetrics` (not by measuring rendered children). It also sets `Layout.minimumWidth`, `Layout.preferredWidth`, and `Layout.maximumWidth` to the same value so Plasma's panel layout respects the exact size. Width is dynamic: changes when `isRunning` toggles.

### Translations
All user-visible strings use `i18n("...")` or `i18np("singular", "plural", count)`.  
Translation files live in `contents/locale/<lang>/LC_MESSAGES/plasma_applet_com.github.pomodoro-todo.po`.  
Run `./install.sh` to compile `.po` → `.mo` via `msgfmt`.

## Common Tasks

### Add a new config key
1. Add `<entry name="myKey" type="String"><default>val</default></entry>` to `contents/config/main.xml`
2. Use `plasmoid.configuration.myKey` in QML
3. Add `property type cfg_myKey: plasmoid.configuration.myKey` to `ConfigTimer.qml` if it needs a UI

### Add a new translatable string
1. Wrap in `i18n("My string")` in QML
2. Add `msgid / msgstr` pairs to both `.po` files under `contents/locale/`
3. Re-run `./install.sh` to recompile

### Test changes
```bash
./install.sh
kquitapp6 plasmashell && kstart plasmashell
```
Or hot-reload a single file (sometimes works):
```bash
plasmashell --replace &
```

### Debug QML errors
```bash
journalctl --user -f | grep plasmashell
```

## Gotchas

- `PlasmaCore.DataSource` — **removed in Plasma 6**. Use `org.kde.notification` for notifications.
- `Row` doesn't vertically center children; use `RowLayout` with `Layout.alignment: Qt.AlignVCenter`.
- `RowLayout.implicitWidth` correctly excludes `visible: false` children, making it safe for dynamic width calculations.
- `onAccepted` on `TextField` is the correct signal for Enter key (not `Keys.onReturnPressed`).
- Context menu actions: in Plasma 6 the `function action_<name>()` naming convention no longer works. Use `plasmoid.action("name").triggered.connect(function() { ... })` instead.
- Config page `cfg_*` properties must match the exact key name in `main.xml`.
