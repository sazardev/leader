<!-- name: Expressive -->
<!-- desc: springs, shared-element transitions and choreography: motion as part of the brand -->
<!-- for: gui -->

## Motion

- Springs instead of fixed curves: default `stiffness 380, damping 30` (snappy), `stiffness 200, damping 26` (gentle); interruptible at any time.
- Shared-element transitions between list and detail (View Transitions API on web, Hero/matchedGeometry on mobile).
- Choreography: related elements stagger by 30-50 ms, never more than 5 in a sequence; total under 500 ms.
- Micro-interactions on success/error (a check that draws, a field that shakes once).

## Accessibility

- With reduced motion, springs become 150 ms fades and shared-element transitions become cross-fades.

## Rules for agents

- Animate only `transform`, `opacity` and `filter`; measure 60 fps on a mid-range phone.
