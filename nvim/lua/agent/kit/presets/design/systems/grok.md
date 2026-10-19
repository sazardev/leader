<!-- name: Grok -->
<!-- desc: dark-first X-style UI: black surfaces, high contrast, blue accent, dense real-time feed, sharp corners -->

# DESIGN.md: Grok

The look of xAI's Grok: a dark, high-contrast, X-like surface with black and near-black backgrounds, a bright blue accent,
dense information, and sharp geometry that feels fast and direct. Source: Grok's web UI (grok.com / X); values are from the
product and marked "(approx.)" where they vary between versions or themes.

## Principles

- **Dark first**: the default experience is near-black; light mode, if offered, is secondary.
- **High contrast**: white text on black surfaces, with grays only for secondary information.
- **Real-time and direct**: content updates live; feedback is immediate and unambiguous.
- **Dense but scannable**: lots of information per screen, aligned on a strict grid, with clear hierarchy.
- **Brand-aligned**: geometry and motion match the host platform (X): sharp, fast, no softness.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` (approx.) | `#000000` | App background |
| `surface` | `#F7F7F7` (approx.) | `#16181C` (approx.) | Cards, panels, sidebars |
| `surface-raised` | `#FFFFFF` (approx.) | `#1D1F23` (approx.) | Menus, popovers, modals |
| `text` | `#0F1419` (approx.) | `#E7E9EA` | Body text, headings |
| `text-muted` | `#536471` (approx.) | `#71767B` (approx.) | Secondary text, metadata |
| `text-faint` | `#8B98A5` (approx.) | `#536471` (approx.) | Placeholders, hints |
| `border` | `#EFF3F4` (approx.) | `#2F3336` (approx.) | 1px separators |
| `accent` | `#1D9BF0` | `#1D9BF0` | Primary buttons, links, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#00BA7C` (approx.) | `#00BA7C` (approx.) | Success states |
| `warning` | `#FFD400` (approx.) | `#FFD400` (approx.) | Warnings |
| `danger` | `#F4212E` (approx.) | `#F4212E` (approx.) | Destructive actions |

- Accent is a bright X blue used for primary actions, links and focus; large surfaces stay black/gray.
- Dividers and borders are low-contrast in dark mode; separation comes from lightness steps.

## Typography

Fonts: system sans-serif (approx. Inter / platform UI) for all UI text, and a monospace for code (approx. system mono).
(approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Display | 28–40px / 1.1 | 700 | Hero and empty-state headings (approx.) |
| Heading | 18–22px / 1.2 | 700 | Section and panel titles (approx.) |
| Body | 15px / 1.4 | 400 | Conversation and feed text (approx.) |
| UI | 13–14px / 1.3 | 400–600 | Sidebar rows, buttons, inputs (approx.) |
| Small | 12px / 1.3 | 400–500 | Metadata, timestamps, hints (approx.) |
| Code | 13–14px / 1.5 | 400 | Code blocks and inline code (approx.) |

- Headings are bold and tight; body text stays compact with modest line height for density.
- Tabular figures for counts, metrics and timestamps where alignment matters.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16, 20, 24 (approx.).
- Feed and conversation content uses a centered column with side gutters on wide screens.
- Sidebar ~260–300px on desktop; collapses to a drawer on narrow screens.
- Composer is pinned at the bottom with a rounded input area and send button.

## Shape and elevation

- Radius: 4px (buttons, inputs), 8px (cards, code blocks), 12–16px (modals, popovers) (approx.).
- Borders: 1px, low contrast; surfaces separate by lightness steps and borders, not shadows.
- Elevation for floating layers only: a soft large shadow plus a 1px border on menus, popovers and modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 80–120ms (approx.) |
| duration-default | 120–200ms (approx.) |
| easing | ease-out (approx.) |

- Streaming and feed updates are immediate; auto-scroll is smooth and pauses on user scroll.
- Hover and state changes are snappy; menus fade/slide in quickly; nothing animates longer than ~250ms.
- Reduced motion: no slides, fades only.

## Components

- **Conversation / feed**: alternating turns or posts; assistant answers render as Markdown with code blocks, lists and tables.
- **Composer**: rounded multi-line input with a send button, attachment and tools entry points, and a stop button while streaming.
- **Sidebar**: conversation or navigation list grouped by recency, search, and a new-chat action; collapsible.
- **Code blocks**: surface background, language label, and copy button on hover; horizontal scroll for wide code.
- **Buttons**: primary (accent fill), secondary (subtle surface + border), ghost for most actions.
- **Feedback**: toasts and inline notices; destructive actions use a confirm dialog.
- **Empty states**: one sentence plus the composer; no marketing chrome inside the app.

## Accessibility

- Text and `text-muted` meet 4.5:1 on their surfaces in both themes.
- Focus visible on every interactive element (accent ring) for keyboard users.
- Keyboard navigation covers new chat, search, send, and stop; shortcuts are discoverable.
- Color never alone for status; icons and labels accompany color.
- Targets ≥ 24px on desktop, 44px on touch.

## Rules for agents

- Implement tokens as CSS variables; components never hardcode colors; support light and dark themes from the same tokens.
- Keep the conversation column readable: constrain width, use generous line height, and avoid dense UI inside answers.
- Streaming must not cause layout jumps; reserve space and scroll smoothly.
- Use the accent sparingly (primary actions, focus, links); keep surfaces dark and high-contrast.
- Prefer subtle borders and lightness steps over shadows; floating layers are the only elevated surfaces.
- Every new action is keyboard reachable and shown in its tooltip/menu row.
