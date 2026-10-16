<!-- name: Radix Themes -->
<!-- desc: Radix Themes: 12-step color scales, accent + gray, radius and scaling props, accessible primitives -->

# DESIGN.md: Radix Themes

Radix Themes (by WorkOS), built on Radix Primitives and Radix Colors. Source of truth: radix-ui.com/themes. The whole UI is
configured by one `<Theme>`: `accentColor`, `grayColor`, `radius`, `scaling`, `appearance`, `panelBackground`.

## Principles

- **12-step scales**: every color has 12 steps with a fixed purpose, so contrast is predictable in light and dark.
- **Configure, don't override**: theme props change the whole app; component props (`size`, `variant`, `color`) change one.
- **Accessible primitives**: keyboard, focus and ARIA come from Radix Primitives.
- **Quiet defaults**: neutral surfaces, one accent, restrained motion.

## Color

Radix Colors 12-step scale (each step's purpose):

| Step | Use |
| --- | --- |
| 1–2 | App background, subtle background |
| 3–5 | UI element background: normal, hover, pressed/selected |
| 6–8 | Borders: subtle, element, hover/focus |
| 9–10 | Solid backgrounds (buttons), hovered solid |
| 11–12 | Low-contrast text, high-contrast text |

| Token | Light (indigo / slate) | Dark (indigo / slate) | Use |
| --- | --- | --- | --- |
| `--accent-9` | `#3E63DD` | `#3E63DD` | Solid buttons, focus |
| `--accent-11` | `#3A5BC7` | `#9EB1FF` | Accent text, links |
| `--accent-contrast` | `#FFFFFF` | `#FFFFFF` | Text on accent-9 |
| `--gray-1` | `#FCFCFD` | `#111113` | App background |
| `--gray-3` | `#F0F0F3` | `#212225` | Element background |
| `--gray-6` | `#D9D9E0` | `#363A3F` | Subtle borders |
| `--gray-11` | `#60646C` | `#B0B4BA` | Secondary text |
| `--gray-12` | `#1C2024` | `#EDEEF0` | Primary text |
| `--red-9` | `#E5484D` | `#E5484D` | Danger |
| `--green-9` | `#30A46C` | `#30A46C` | Success |
| `--amber-9` | `#FFC53D` | `#FFC53D` | Warning |

- `accentColor` choices include tomato, red, crimson, pink, plum, purple, violet, iris, indigo, blue, cyan, teal, jade, green, grass, orange, amber, gold, bronze, brown, sky, mint, lime, yellow; gray: gray, mauve, slate, sage, olive, sand (or `auto`).
- Alpha variants (`--accent-a3`) for overlays on any background.

## Typography

Font: system stack by default (`--default-font-family`); set a brand font through `--default-font-family` / `--heading-font-family`.

| Size token | Font size / line height | Use |
| --- | --- | --- |
| `--font-size-1` | 12 / 16 | Captions |
| `--font-size-2` | 14 / 20 | Default UI text |
| `--font-size-3` | 16 / 24 | Body |
| `--font-size-4` | 18 / 26 | Lead |
| `--font-size-5` | 20 / 28 | Heading 5 |
| `--font-size-6` | 24 / 30 | Heading 4 |
| `--font-size-7` | 28 / 36 | Heading 3 |
| `--font-size-8` | 35 / 40 | Heading 2 |
| `--font-size-9` | 60 / 60 | Display |

Weights: light 300, regular 400, medium 500, bold 700. All values multiply with `scaling` (90%–110%).

## Spacing and layout

- Space scale `--space-1` … `--space-9`: 4, 8, 12, 16, 24, 32, 40, 48, 64px (× scaling).
- Layout components: `Box`, `Flex`, `Grid`, `Container` (sizes 1–4: 448, 688, 880, 1136px), `Section` (vertical rhythm).
- Responsive props per breakpoint: initial, xs 520, sm 768, md 1024, lg 1280, xl 1640px.

## Shape and elevation

- `radius` theme prop: none, small, medium (default), large, full; components derive `--radius-1`…`--radius-6` (medium: 3, 4, 6, 8, 12, 16px).
- Shadows `--shadow-1` … `--shadow-6` (inset for fields, raised for cards, overlay for popovers/dialogs).
- `panelBackground`: `solid` or `translucent` (blurred panels for cards, menus).

## Motion

- Restrained: popovers and dialogs fade/scale ~150–200ms (approx.); no motion for layout changes.
- Radix Primitives expose `data-state="open|closed"` for CSS animations; respect `prefers-reduced-motion`.

## Components

- **Button** variants: `solid` (primary), `soft`, `surface`, `outline`, `ghost`; sizes 1–4; `color` prop for semantic tones (`red` for destructive).
- **Card**, **Inset**, **Separator** for grouping; **Table** (`variant="surface"`), **DataList** for key/value.
- **Forms**: `TextField.Root`, `TextArea`, `Select`, `Checkbox`, `RadioGroup`, `Switch` with `Text as="label"`.
- **Overlays**: `Dialog`, `AlertDialog` (destructive confirmations), `Popover`, `DropdownMenu`, `Tooltip`.
- **Feedback**: `Callout` for inline messages, `Badge` for status, `Spinner`/`Skeleton` for loading.

## Accessibility

- Steps 11/12 on steps 1/2 meet APCA/WCAG text contrast; step 9 solids pair with `--accent-contrast`.
- Focus rings use `--focus-8`; never remove `:focus-visible` styles.
- Radix Primitives handle keyboard navigation, focus trapping and ARIA; keep their structure.
- Respect `prefers-reduced-motion` and test with `appearance="dark"`.

## Rules for agents

- Wrap the app in `<Theme accentColor grayColor radius scaling appearance>` from `@radix-ui/themes` and import `@radix-ui/themes/styles.css` once.
- Use Radix Themes components and their props; custom CSS reads `var(--accent-9)`, `var(--gray-12)`, `var(--space-3)`, never hex.
- Choose colors by step purpose (backgrounds 1–5, borders 6–8, solids 9–10, text 11–12).
- Layout with `Flex`/`Grid`/`Box` props (`gap="3"`, `p="4"`), responsive objects for breakpoints.
- Destructive confirmations use `AlertDialog` with `color="red"`.
