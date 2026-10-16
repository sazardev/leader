<!-- name: Glass -->
<!-- desc: translucent surfaces with backdrop blur, a light border and solid fallbacks -->
<!-- for: gui -->
<!-- default: glass -->

## Shape and elevation

- Glass surfaces: `background: color-mix(in oklch, var(--surface) 60%, transparent)`, `backdrop-filter: blur(16px) saturate(140%)`, 1 px border `rgb(255 255 255 / 0.18)` (dark) or `rgb(0 0 0 / 0.08)` (light).
- Only on floating layers (navigation, sheets, popovers), never stacked more than two deep.

## Accessibility

- Text on glass keeps 4.5:1 against the worst background behind it; with `prefers-reduced-transparency` or no `backdrop-filter` support, surfaces become solid.

## Rules for agents

- Use `@supports (backdrop-filter: blur(1px))` for the glass styles and keep the solid version as the default.
