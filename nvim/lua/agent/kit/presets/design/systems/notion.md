<!-- name: Notion -->
<!-- desc: calm document UI: warm grays, content-first blocks, minimal chrome, 9 text and background colors -->

# DESIGN.md: Notion

The calm, content-first look of Notion: a document is a stack of blocks, chrome appears only on hover, warm grays instead of
pure black, and color is used sparingly through a small named palette. Source: Notion's product UI (no public design system;
values are taken from the product and marked "(approx.)" where they vary between versions).

## Principles

- **Content is the interface**: the page is the product; chrome (handles, menus, toolbars) appears on hover or selection.
- **Calm**: warm low-contrast grays, no heavy borders, no strong shadows; color only when the user adds it.
- **Blocks**: every piece of content is a block that can be moved, turned into another type, nested or linked.
- **Progressive disclosure**: simple by default (type and go), power through `/` commands, `@` mentions and hover menus.
- **Text-first hierarchy**: headings and spacing, not boxes, structure the page.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `text` | `#37352F` | `rgba(255,255,255,0.81)` | Body text |
| `text-muted` | `rgba(55,53,47,0.65)` | `rgba(255,255,255,0.46)` | Secondary text, properties |
| `text-faint` | `rgba(55,53,47,0.45)` (approx.) | `rgba(255,255,255,0.28)` (approx.) | Placeholders |
| `background` | `#FFFFFF` | `#191919` | Page |
| `sidebar` | `#F7F7F5` | `#202020` | Sidebar, secondary surfaces |
| `hover` | `rgba(55,53,47,0.08)` | `rgba(255,255,255,0.055)` | Hover on rows and buttons |
| `divider` | `rgba(55,53,47,0.09)` | `rgba(255,255,255,0.094)` | Dividers, table lines |
| `accent` | `#2383E2` | `#2383E2` | Primary buttons, links, selection, focus |
| `danger` | `#EB5757` (approx.) | `#EB5757` (approx.) | Delete actions |

Named block colors (text / background, light theme, approx.):

| Name | Text | Background |
| --- | --- | --- |
| Gray | `#787774` | `#F1F1EF` |
| Brown | `#9F6B53` | `#F4EEEE` |
| Orange | `#D9730D` | `#FAEBDD` |
| Yellow | `#CB912F` | `#FBF3DB` |
| Green | `#448361` | `#EDF3EC` |
| Blue | `#337EA9` | `#E7F3F8` |
| Purple | `#9065B0` | `#F6F3F9` |
| Pink | `#C14C8A` | `#FAF1F5` |
| Red | `#D44C47` | `#FDEBEC` |

- These nine colors are the whole user palette (tags, callouts, highlights, select options); never introduce a tenth.
- Success/warning/info reuse Green/Yellow/Blue from the palette.

## Typography

Font stack: `ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, "Apple Color Emoji", Arial, sans-serif`; optional serif (`Lyon-Text, Georgia, serif`) and mono (`iawriter-mono, Nitti, Menlo, Courier, monospace`) page styles.

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Page title | 40px / 1.2 | 700 | Page title (approx.) |
| Heading 1 | 1.875em / 1.3 | 600 | Sections |
| Heading 2 | 1.5em / 1.3 | 600 | Subsections |
| Heading 3 | 1.25em / 1.3 | 600 | Groups |
| Body | 16px / 1.5 | 400 | Text blocks |
| UI | 14px / 1.4 (approx.) | 400–500 | Sidebar, menus, properties |
| Small | 12px / 1.4 (approx.) | 400 | Meta, captions, hints |

- "Small text" page option reduces body to 14px. Inline code: mono at 85%, red-tinted text on a light gray background.

## Spacing and layout

- Page width 708px of text (default) or 900px+ with "Full width"; side padding ~96px on wide screens (approx.).
- Blocks are separated by ~2–4px (approx.); paragraphs breathe through line height, not margins. Headings get extra top space (~1.4em for H1).
- Sidebar 240px (resizable), collapsible; top bar ~45px with breadcrumbs and page actions (approx.).
- Spacing steps used in UI (approx.): 2, 4, 6, 8, 12, 14, 16, 24, 32px.

## Shape and elevation

- Radius 3px for blocks, buttons, tags and hover backgrounds; 4–6px for menus and popovers (approx.).
- No borders on content; dividers are hairlines in `divider`.
- Elevation only for floating layers (menus, popovers, modals): soft layered shadow, e.g. `rgba(15,15,15,0.05) 0 0 0 1px, rgba(15,15,15,0.1) 0 3px 6px, rgba(15,15,15,0.2) 0 9px 24px` (approx.).

## Motion

| Token | Value |
| --- | --- |
| hover | 20ms ease-in (background appears near-instantly) (approx.) |
| menu/popover | 150–200ms ease-out fade + slight scale (approx.) |
| sidebar toggle | ~200ms ease (approx.) |

- Motion is nearly invisible: it smooths state changes, never decorates. No bounces.
- Drag and drop shows a blue drop line where the block will land.
- Reduced motion: no scale, fades only.

## Components

- **Blocks**: text, headings, to-do, toggle, bulleted/numbered lists, callout (icon + colored background), quote, divider, code, image, embed, database views. Hover shows the `⋮⋮` drag handle and `+` on the left.
- **Slash menu** (`/`): searchable list of block types with icon, name and short description; keyboard first.
- **Buttons**: mostly text buttons with hover background; one blue filled button for primary actions in dialogs (Share, Publish).
- **Databases**: table, board, list, gallery, calendar, timeline views of the same data; properties as compact rows with icon + muted label.
- **Menus**: compact rows (~28px), icon + label + optional shortcut on the right, groups separated by dividers.
- **Empty states**: a gray placeholder line inside the block ("Type '/' for commands"), never illustrations in content.

## Accessibility

- `text-muted` on white is borderline for small text: use it only for secondary information, never for essential labels; body text uses `text`.
- Hover-only affordances must also be reachable by keyboard (focus shows the same handles and menus).
- Focus ring: 2px `accent` (approx.) visible on every interactive element.
- Named colors are decorative: a tag's meaning must be in its text, not only its color.
- Targets: menu rows and buttons at least 24px high on desktop, 44px on touch.

## Rules for agents

- Implement colors as CSS variables (`--text`, `--text-muted`, `--bg`, `--sidebar`, `--hover`, `--divider`, `--accent`, `--color-<name>`, `--bg-<name>`) with a `[data-theme="dark"]` override; never hardcode hex in components.
- Build content as blocks: a block component with type, children and hover handle; transformations between types keep the text.
- Show chrome on hover/focus, hide it otherwise; never permanent borders around content.
- Use the nine named colors only; any new color need goes through this file.
- Keep text measure at 708px (or full width option); never stretch body text across the window.
- Keyboard first: `/` menu, `@` mentions, `Cmd/Ctrl+K` search, arrow navigation in every menu.
