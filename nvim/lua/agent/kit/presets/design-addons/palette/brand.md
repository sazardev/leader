<!-- name: Brand palette -->
<!-- desc: keep the design's own palette and derive tints and shades from one brand color in OKLCH -->
<!-- for: all -->
<!-- default: systems -->

## Color

- Keep the preset's palette; the brand color (one hex, TODO) replaces `primary`/`accent`.
- Tints and shades in OKLCH: same hue, lightness steps 98, 95, 90, 80, 70, 60, 50, 40, 30, 20, 15% with chroma reduced near the extremes; each step checked for contrast with its `on-` color.
- Neutrals take a trace of the brand hue (chroma ≤ 0.01) so greys feel related.
- These values replace the base palette's for the same roles; contrast pairs are checked again after the swap.
