<!-- name: Web, responsive -->
<!-- desc: mobile-first layouts from 360 px to wide screens: breakpoints, fluid type, container queries -->
<!-- for: gui -->
<!-- default: gui -->

## Spacing and layout

- Mobile first: design at 360 px, then adapt at `sm 640`, `md 768`, `lg 1024`, `xl 1280`, `2xl 1536` px.
- Fluid type and spacing with `clamp()` between the smallest and largest breakpoint (e.g. body `clamp(1rem, 0.95rem + 0.25vw, 1.125rem)`).
- Components adapt to their container with container queries (`@container`), not to the viewport.
- Content measure 60-75 characters; the page never scrolls sideways at 320 px.

## Components

- Navigation collapses to a menu button below `md`; tables become stacked cards or scroll inside their own container.
- Hover is an enhancement: every action works with touch and keyboard (`@media (hover: hover)` for hover-only styles).

## Rules for agents

- Test every screen at 360, 768, 1280 and 1920 px wide and at 200% browser zoom.
- Use relative units (`rem`, `%`, `ch`) for sizes; `px` only for borders and hairlines.
