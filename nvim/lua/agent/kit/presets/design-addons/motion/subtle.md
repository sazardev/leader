<!-- name: Subtle -->
<!-- desc: short, quiet transitions that explain changes: 120-200 ms, ease-out, opacity and small movement -->
<!-- for: all -->
<!-- default: gui -->

## Motion

- Durations: 120 ms (hover, press), 200 ms (enter/leave of small elements), 280 ms (panels, dialogs); exits 30% shorter than entries.
- Easing: `cubic-bezier(0.2, 0, 0, 1)` for entering, `cubic-bezier(0.4, 0, 1, 1)` for leaving; movement ≤ 8 px, mostly opacity.
- Only `opacity` and `transform` animate; never layout properties.

## Rules for agents

- Reuse the duration and easing tokens; no ad-hoc timings.
