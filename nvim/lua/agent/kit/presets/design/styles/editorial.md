<!-- name: Editorial -->
<!-- desc: magazine style: serif display, grotesk body, strong column grid, pull quotes, generous measure -->

# DESIGN.md: Editorial

A reading-first style borrowed from magazines: a confident serif display, a neutral grotesk for text and UI, a strict
column grid, drop caps and pull quotes. Suits blogs, publications, documentation sites and long-form product stories.

## Principles

- **Reading comes first**: measure, rhythm and contrast are tuned for long text.
- **Type is the image**: big serif headlines carry the page; decoration is minimal.
- **The grid is visible in the rhythm**: columns and baseline keep everything aligned.
- **Contrast of voices**: serif for display, grotesk for text and interface.
- **Restraint with color**: ink, paper and one accent.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `paper` | `#FBF8F3` | `#121110` | Background |
| `surface` | `#F3EEE6` | `#1B1917` | Asides, captions boxes |
| `ink` | `#1A1714` | `#EDE7DF` | Body text |
| `ink-muted` | `#5E574F` | `#A8A097` | Bylines, captions |
| `rule` | `#D9D0C3` | `#3A3530` | Hairline rules |
| `accent` | `#B4232A` | `#F07167` | Kicker labels, links, drop caps |
| `on-accent` | `#FFFFFF` | `#121110` | Text on accent |
| `highlight` | `#FFF1B8` | `#4A3F14` | Text highlight |
| `success` | `#2F6B3B` | `#7FD49B` | States |
| `warning` | `#8A5A00` | `#F5C451` | States |
| `danger` | `#B4232A` | `#F07167` | Errors |

## Typography

Display: a high-contrast serif (Fraunces, Playfair Display, Source Serif 4 Display). Text/UI: a grotesk (Inter, Söhne-like
`"Helvetica Neue", Arial`). Body text may use the serif's text cut for articles.

| Role | Size / line height | Weight | Font | Use |
| --- | --- | --- | --- | --- |
| headline-xl | 64 / 68 | 600 | serif | Cover headlines |
| headline | 44 / 50 | 600 | serif | Article titles |
| deck | 22 / 32 | 400 | serif italic | Standfirst under the title |
| h2 | 28 / 34 | 600 | serif | Article sections |
| kicker | 13 / 16 | 700, uppercase, +0.08em | grotesk | Section labels |
| body | 19 / 31 | 400 | serif text or grotesk | Article text |
| ui | 15 / 22 | 500 | grotesk | Navigation, buttons |
| caption | 13 / 18 | 400 | grotesk | Captions, bylines |
| pull-quote | 32 / 40 | 500 italic | serif | Pull quotes |

Measure 60–72 characters; hanging punctuation for quotes; old-style figures in text, lining in tables.

## Spacing and layout

- Baseline 8px; vertical rhythm in multiples of the body line height (31px ≈ 4 × 8 − 1, round to 32 for blocks).
- Grid: 12 columns, 24px gutters, max width 1280px; article text spans 7 columns centered (≈ 680px), images may break out to 10 or full width.
- Margins: 64px between sections, 32px between paragraphs groups, 0 between paragraphs (indent 1em instead, or 16px spacing — choose one).

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius` | 0 | Everything (print heritage) |
| `rule-hair` | 1px `rule` | Between sections, under bylines |
| `rule-heavy` | 3px `ink` | Above kickers, section starts |
| `shadow` | none | No elevation; layering by rules and space |

## Motion

| Token | Value |
| --- | --- |
| `duration` | 180ms |
| `ease` | `cubic-bezier(0.4, 0, 0.2, 1)` |

- Only links (underline grows), images (fade in on load) and menus move. No scroll-jacking, no parallax.
- Reduced motion: no fades.

## Components

- **Article header**: kicker, headline, deck, byline row (author, date, reading time), hero image with caption.
- **Drop cap**: first paragraph, 3 lines tall, `accent`.
- **Pull quote**: between paragraphs, spans 9 columns, rule-heavy above.
- **Links**: ink with 1px underline offset 3px; hover = accent.
- **Navigation**: masthead with logo in serif, sections in kicker style.
- **Lists of articles**: image, kicker, headline, deck; grid of 3 / 2 / 1.
- **States**: empty search (one sentence + suggested sections), loading (text skeleton lines at body measure).

## Accessibility

- Body contrast ≥ 7:1 (ink on paper exceeds it); muted text ≥ 4.5:1.
- Real heading order (h1 per article); pull quotes are `<blockquote>`/`<aside>` with `aria-hidden` if duplicated text.
- Text resizes to 200% without horizontal scroll; line height never below 1.4 for body.
- Links distinguishable without color (underline).

## Rules for agents

- Use the type roles above only; never set a font size outside the scale.
- Keep article text at the measure (max-width ~68ch); never full-width paragraphs.
- Load at most two families (serif + grotesk), `font-display: swap`, subset to used glyphs.
- Images always have captions and alt text; credits in caption style.
- No rounded corners and no shadows: separation is space and rules.
