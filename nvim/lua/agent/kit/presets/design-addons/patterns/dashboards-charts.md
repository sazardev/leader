<!-- name: Dashboards and charts -->
<!-- desc: KPI cards, chart choice, axes, legends, color-blind-safe series, time ranges and skeletons -->
<!-- for: all -->

## Components

- GUI: KPI card: label (muted, 12-13 px), value (28-32 px, tabular figures), a delta with arrow and sign and the comparison period ("+4.2% vs last week"), optional 24 px high sparkline; 4 cards per row maximum; the most important metric comes first at top left.
- GUI: delta color follows meaning, not direction: success for good, danger for bad, neutral for unknown; always pair color with the arrow and sign.
- GUI: choose the chart by question: trend over time is a line; comparison between categories is a horizontal bar sorted by value; part-to-whole with 5 or fewer parts is a stacked bar or donut with the total in the center; distribution is a histogram; avoid 3D, dual axes and pie charts with many slices.
- GUI: axes start at zero for bars; label axes with units; at most 5-6 gridlines in a subtle border color; format numbers compactly (1.2k, 3.4M) and consistently; dates match the selected range.
- GUI: legends sit above or beside the chart, interactive (click toggles a series), and series are also directly labelled at the line ends when 3 or fewer; at most 6 series, group the rest as "Other".
- GUI: series colors come from a categorical palette that is color-blind safe and distinguishable in grayscale; also vary shape or dash style for lines; sequential data uses one hue by lightness.
- GUI: time range control at the top right: presets (Today, 7d, 30d, 90d, Custom) plus compare toggle; the active range is always printed with explicit dates in the chart header.
- GUI: tooltips on hover and keyboard focus show exact values for all series at that x position; click a mark drills into the underlying records.
- GUI: loading shows skeletons shaped like the final cards and charts; per-widget errors show "Could not load" with "Retry" inside the widget, never blanking the whole dashboard; empty widgets say "No data for this period".
- TUI: sparklines with block characters, horizontal bars using partial blocks, values right-aligned beside them; ranges switched with `[` and `]`.

## Accessibility

- Provide a data table alternative or summary text for each chart ("Revenue rose 12% over 30 days"); never encode meaning by color alone; tooltips are reachable by keyboard.

## Rules for agents

- Every number on a dashboard shows its unit, period and last-updated time.
- Never truncate axes to exaggerate a change.
