<!-- name: Swiss / International -->
<!-- desc: Swiss typographic style: strict grid, grotesk type, asymmetric layouts, black, white and one red -->

# DESIGN.md: Swiss / International

The International Typographic Style (Müller-Brockmann, Vignelli): a strict modular grid, a neo-grotesk typeface, flush-left
ragged-right text, asymmetric compositions and almost no color besides black, white and one red. Clarity through order.

## Principles

- **The grid is law**: every element aligns to columns and the baseline.
- **Typography is the image**: size, weight and placement create hierarchy; decoration is unnecessary.
- **Asymmetry with balance**: compositions are off-center but weighted.
- **Objective tone**: factual copy, no ornament, no illustration unless it is information.
- **One accent**: red marks the one thing to notice.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#0D0D0D` | Page |
| `surface` | `#F4F4F2` | `#1A1A1A` | Sections, inputs |
| `text` | `#111111` | `#F2F2F2` | Text |
| `text-muted` | `#5C5C5C` | `#A3A3A3` | Captions |
| `rule` | `#111111` | `#F2F2F2` | 1px/2px rules |
| `accent` | `#E30613` (Swiss red, approx.) | `#FF2A36` (approx.) | Key action, highlights |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on red |
| `success` | `#1E7F3C` | `#4CC172` | States |
| `warning` | `#8A6D00` | `#E5C44C` | States |
| `danger` | `#E30613` | `#FF2A36` | Errors (shares the accent) |
| `focus` | `#111111` | `#F2F2F2` | Focus outline |

## Typography

| Role | Size / line height | Weight | Tracking | Use |
| --- | --- | --- | --- | --- |
| display | 72 / 72 | 700 | -0.02em | Posters, heroes |
| h1 | 48 / 52 | 700 | -0.02em | Titles |
| h2 | 32 / 36 | 700 | -0.01em | Sections |
| h3 | 20 / 24 | 600 | 0 | Subsections |
| body | 17 / 26 | 400 | 0 | Text |
| caption | 13 / 18 | 400 | 0.01em | Captions, meta |
| label | 12 / 16 | 600, uppercase | 0.06em | Labels, nav |

- Typeface: Helvetica Neue, Neue Haas Grotesk, Inter or Söhne (approx. alternatives); one family only.
- Flush left, ragged right; never justified, never centered body text. Tabular figures in data.

## Spacing and layout

- 8px base and baseline grid (body line height 26 → snap blocks to 8px multiples, approx.).
- 12-column grid, 24px gutters, 48–96px outer margins; breakpoints 640, 960, 1280, 1600.
- Content measure 60–75 characters; headings may hang into the left margin column.
- Large white space as a design element: sections separated by 96–160px.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| radius | 0 | Everything |
| rule-thin | 1px `rule` | Lists, tables |
| rule-thick | 4px `rule` | Section starts |
| elevation | none | Hierarchy by position and rules only |

## Motion

| Token | Value | Use |
| --- | --- | --- |
| duration | 150ms | State changes |
| easing | `cubic-bezier(0.4, 0, 0.2, 1)` | Everything |
| transitions | opacity and position along the grid only | Page and panel changes |

- No bounce, no scale; reduced motion = instant.

## Components

- **Buttons**: primary = `accent` fill, no radius, label uppercase; secondary = 2px `rule` border; text buttons underlined on hover.
- **Inputs**: bottom border only (2px `rule`), label above in `label` style.
- **Navigation**: horizontal uppercase labels, active one with a 4px bar above it.
- **Tables**: no vertical lines, 1px rules between rows, numbers right-aligned tabular.
- **Cards**: none; use grid cells with a top rule.
- **Dialogs**: full-bleed white panel aligned to the grid, top rule.
- **Toasts**: black bar with white text, bottom-left.
- **Empty/loading/error**: one large typographic statement + action; loading as a thin progress rule.

## Accessibility

- AA contrast for all text (black/white pairs exceed AAA); red text only ≥ 18px or on white with ≥ 4.5:1 (check `#E30613` ≈ 4.6:1, approx.).
- Focus: 2px solid `focus` outline offset 2px.
- Hierarchy never relies on red alone; underline links.
- Targets ≥ 44×44px even when visually minimal.

## Rules for agents

- Layout with CSS Grid on the 12-column system; every element starts and ends on column lines.
- Tokens as CSS variables; one font family; no radius, no shadows, no gradients.
- Use `accent` once per view for the primary action or key fact.
- Keep line length 60–75ch; never center paragraphs.
