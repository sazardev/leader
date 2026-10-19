<!-- name: Navigation shell -->
<!-- desc: sidebar, top bar, tabs and bottom bar by screen size, current location and breadcrumbs -->
<!-- for: all -->

## Components

- GUI: choose one primary navigation per breakpoint: wide (1024 px and up) a left sidebar 240 px (collapsible to 64 px icon rail); medium a collapsed rail; narrow (under 600 px) a bottom bar with 3-5 destinations, each icon plus label, 56 px high.
- GUI: top bar 56 px holds the page title, global search, and account menu; it never repeats the sidebar items.
- GUI: current location is always visible: the active item uses the primary color on a tinted surface plus a 3 px indicator, and sets `aria-current="page"`; color is never the only cue.
- GUI: 7 or more destinations are grouped under small section labels in the sidebar; rarely used ones live under a "More" item; at most 2 levels of nesting.
- GUI: breadcrumbs only for hierarchies 3 or more levels deep: `Projects / Apollo / Settings`, the last item plain text, middle items collapse to "..." on narrow screens.
- GUI: tabs switch views of the same object (Overview, Activity, Settings), max 6, never used for navigation between unrelated pages; the active tab persists in the URL.
- GUI: preserve scroll position and filters when returning to a list from a detail page; the browser back button must always work.
- TUI: a header line with the current view name and numbered tabs (`1 Home  2 Logs  3 Settings`), switched with number keys or `Tab`; a footer line shows the 4-6 most relevant keys; `?` opens the full list.
- TUI: nested views show a path in the header (`Projects > Apollo`), `Esc` or `h` goes up one level.

## Accessibility

- Provide a "Skip to content" link; navigation is a `nav` landmark with a label; the collapsible sidebar toggle reports `aria-expanded`; focus order is nav, then main.

## Rules for agents

- The same destination has the same name and icon everywhere.
- Never place primary navigation in a hamburger on wide screens.
- Every screen answers "where am I" without reading the URL.
