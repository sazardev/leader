<!-- name: Reduced motion -->
<!-- desc: honour the user's motion preference: no movement, only short fades -->
<!-- for: all -->
<!-- default: all -->

## Accessibility

- With `prefers-reduced-motion: reduce` (or the OS/app setting), movement is replaced by ≤ 150 ms opacity fades; parallax, auto-playing animation and spinners that move across the screen are removed.

## Rules for agents

- Every animation is behind the motion preference check; test with it on.
