# Pomodoro Todo — KDE Plasma Widget

![Screenshot](screenshot.png)

A KDE Plasma 6 panel widget that combines a **Pomodoro timer** with a **todo list** — everything you need to stay focused, right in your taskbar.

---

## Features

**Pomodoro Timer**
- Focus sessions (default 25 min) → Short breaks (5 min) → Long break after every 4 sessions (15 min)
- Session dots showing progress through a Pomodoro cycle
- Start / Pause / Reset Current / Reset All / Skip controls
- Timer countdown shown directly in the panel bar while running
- Desktop notifications when each session ends (toggleable)

**Todo List**
- Add and remove tasks
- Check off completed tasks (shown as strikethrough)
- Expand any task to add a longer description
- Tasks persist across sessions (saved in widget config)
- Clear all tasks with confirmation dialog

**Fully Configurable**
- Focus and break durations
- Active color (focus) and break color
- 4 separate tray icons: Focus / Paused+Idle / Short Break / Long Break
- Panel display mode: icon + timer, icon only, or timer only
- Notifications on/off

**Localization**
- English (default)
- Portuguese — Brazil (pt_BR)
- Simplified Chinese (zh_CN)
- Falls back to English automatically

---

## Requirements

- KDE Plasma 6
- `gettext` (for compiling translations): `sudo pacman -S gettext`

---

## Installation

```bash
git clone https://github.com/otavioschwanck/pomodoro-todo-plasma
cd pomodoro-todo-plasma
./install.sh
```

Then restart Plasma:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

Finally, right-click the panel → **Add Widgets** → search for **Pomodoro Todo**.

---

## Usage

- **Left-click** the tray icon to open/close the popup
- **Right-click** the tray icon for quick actions (Start, Pause, Reset, Skip, Clear Tasks)
- In the popup, press **Enter** or click **Add** to create a task
- Click **▼** on a task to expand it and write a description
- Go to **Right-click → Configure…** to adjust durations, colors, icons and notifications

---

## File Structure

```
pomodoro-todo/
├── metadata.json               # Widget metadata (id, author, license)
├── screenshot.png              # Cover image
├── install.sh                  # Build + install script
├── contents/
│   ├── config/
│   │   ├── main.xml            # KConfigXT schema (all settings)
│   │   └── config.qml          # Config dialog page list
│   ├── locale/
│   │   ├── pt_BR/LC_MESSAGES/  # Brazilian Portuguese .po/.mo
│   │   └── zh_CN/LC_MESSAGES/  # Simplified Chinese .po/.mo
│   └── ui/
│       ├── main.qml            # Root PlasmoidItem — all state + layout
│       ├── TodoItem.qml        # Single task row delegate
│       └── ConfigTimer.qml     # Configure dialog page
```

---

## License

GPL-2.0-or-later. Free to use, fork and modify.

---

## Author

**Otávio Schwanck dos Santos** — [otavioschwanck@gmail.com](mailto:otavioschwanck@gmail.com)
