<!-- name: Accessibility -->
<!-- desc: WCAG 2.2 AA: semantic markup, keyboard, visible focus, labels, contrast, reduced motion, tested -->

### Accessibility

- **WCAG 2.2 AA** is the minimum bar for every screen, not a later phase.
- **Semantic elements first**: `button` for actions, `a` for navigation, headings in order, lists, landmarks; ARIA only when no native element fits.
- **Keyboard**: everything works with the keyboard alone, in a logical tab order, with no traps; custom widgets follow the ARIA Authoring Practices patterns.
- **Visible focus** on every interactive element (never `outline: none` without a replacement); focus moves into dialogs and returns on close.
- **Labels**: every input has a visible label; icon-only buttons have an accessible name; images have alt text (empty for decorative ones).
- **Contrast**: text ≥ 4.5:1 (large text ≥ 3:1), UI components and focus indicators ≥ 3:1; color is never the only signal.
- **Targets** at least 24×24 CSS px (44×44 on touch); content reflows at 320px width and 200% zoom.
- **Motion**: respect `prefers-reduced-motion`; nothing flashes more than 3 times per second; auto-playing content can be paused.
- **Errors** are announced, described in text and tied to their field (`aria-describedby`).
- Review check: axe (or equivalent) reports no violations, the flow was done with keyboard only, and a screen reader announces the new UI meaningfully.
