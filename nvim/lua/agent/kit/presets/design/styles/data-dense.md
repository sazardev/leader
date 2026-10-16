<!-- name: Data dense -->
<!-- desc: dashboards and admin tools: 13px UI, tables first, tabular numbers, compact controls, keyboard friendly -->

# DESIGN.md: Data dense

A style for people who work in the product all day: admin panels, ops dashboards, CRMs, financial tools. Small but
readable type, tables as the main component, compact controls, tabular numbers and a calm neutral palette where color
means status.

## Principles

- **Information per pixel**: show more rows, not more chrome.
- **Color means status**: neutral UI; color only for state, severity and data series.
- **Numbers align**: tabular figures, right-aligned numeric columns, consistent units.
- **Keyboard first**: every frequent action has a shortcut; focus is always visible.
- **Stable layout**: nothing jumps when data loads or updates.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#F7F8FA` | `#0E1013` | App background |
| `surface` | `#FFFFFF` | `#15181D` | Panels, tables |
| `surface-alt` | `#F2F4F7` | `#1B1F25` | Zebra rows, headers |
| `border` | `#E2E5EA` | `#2A2F37` | Cell and panel borders |
| `text` | `#111418` | `#E6E8EB` | Text |
| `text-muted` | `#5B636E` | `#9AA3AE` | Labels, secondary columns |
| `accent` | `#2563EB` | `#5B8DEF` | Selection, links, primary action |
| `selection` | `#E8F0FE` | `#1D2B45` | Selected rows |
| `success` | `#1A7F37` | `#3FB950` | Up, ok |
| `warning` | `#9A6700` | `#D29922` | Warnings |
| `danger` | `#CF222E` | `#F85149` | Errors, down |
| `chart-1…6` | `#2563EB #0891B2 #7C3AED #DB2777 #EA580C #65A30D` | lighter variants (approx.) | Series |

## Typography

Font: Inter (with `font-feature-settings: "tnum", "cv11"`), fallback `system-ui, sans-serif`; mono: JetBrains Mono for IDs.

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| page-title | 18 / 24 | 600 | Page header |
| section | 14 / 20 | 600 | Panel titles |
| body | 13 / 20 | 400 | Default UI text, table cells |
| label | 12 / 16 | 500 | Column headers, form labels |
| micro | 11 / 14 | 500 | Badges, chart ticks |
| metric | 24 / 28 | 600 | KPI numbers (tabular) |
| mono | 12 / 18 | 400 | IDs, hashes, code |

## Spacing and layout

- 4px base; scale 2, 4, 6, 8, 12, 16, 24.
- Table rows 32px (compact 28px, comfortable 40px — a density setting); cell padding 8px horizontal.
- Layout: left sidebar 220px (collapsible to 56px), top bar 44px, content fluid; panels in a 12-column grid with 12px gaps.
- Sticky table headers and first column; horizontal scroll inside the table, never the page.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius-sm` | 4px | Inputs, buttons, badges |
| `radius-md` | 6px | Panels, popovers |
| `shadow-pop` | `0 4px 16px rgb(0 0 0 / 0.12)` | Popovers, menus only |
| `border` | 1px `border` | Panels and tables (instead of shadows) |

## Motion

| Token | Value |
| --- | --- |
| `duration-fast` | 80ms |
| `duration-base` | 140ms |
| `ease` | `cubic-bezier(0.2, 0, 0, 1)` |

- Only popovers, toasts and row highlights animate. Data updates flash the changed cell background for 600ms (reduced motion: no flash, a dot marker instead).

## Components

- **Table**: sortable headers (arrow), resizable columns, row selection with checkbox and shift-click ranges, inline row actions on hover, numeric columns right-aligned, empty cells as `—`, pagination or virtualized scroll for > 200 rows.
- **Filters**: a filter bar of chips above the table; saved views.
- **Forms**: inputs 28px high, labels above, inline validation.
- **Buttons**: 28px high; primary (accent), secondary (border), ghost; icon buttons 28×28 with tooltips.
- **KPI card**: label, metric, delta (success/danger + arrow), sparkline.
- **Command palette**: `⌘K`/`Ctrl K` for navigation and actions.
- **States**: empty table (one line + create action), loading (skeleton rows with fixed height), error (inline banner + retry), stale data (timestamp "updated 2m ago").

## Accessibility

- 13px body still meets contrast ≥ 4.5:1 for all text, including muted; status colors never alone (icon or text too).
- Tables are real `<table>` elements with `<th scope>`; sortable headers expose `aria-sort`.
- Focus ring 2px `accent` on every interactive element, including table cells in grid mode.
- Targets may be 28px but spacing between them ≥ 8px; touch mode raises them to 44px.

## Rules for agents

- Every number uses tabular figures and is right-aligned; units in the header, not repeated in cells.
- Never let loading shift the layout: reserve space with skeletons of the final size.
- Status colors only from the tokens, always paired with an icon or label.
- Add a keyboard shortcut for each frequent action and list it in the command palette.
- Prefer one dense table over several cards; paginate or virtualize beyond 200 rows.
