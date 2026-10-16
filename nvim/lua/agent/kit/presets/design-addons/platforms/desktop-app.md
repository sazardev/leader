<!-- name: Desktop app -->
<!-- desc: windows that resize, menus, keyboard shortcuts for everything, multi-pane layouts, native conventions -->
<!-- for: gui -->

## Spacing and layout

- Minimum window 800×600; layouts reflow from one to three panes (sidebar, list, detail) as the window grows; splitters remember their width.
- Respect the OS title bar and window controls (left on macOS, right on Windows/Linux).

## Components

- A menu bar (or app menu) lists every command with its shortcut; context menus on right click.
- Every action has a keyboard shortcut following the platform (`Cmd` on macOS, `Ctrl` elsewhere); a command palette (`Cmd/Ctrl+K`) finds any command.
- Pointer states: hover, pressed, focus ring, and the right cursor (pointer, text, resize).

## Rules for agents

- Never require the mouse: every flow works with the keyboard alone, with visible focus.
- Persist window size, position and pane widths between sessions.
