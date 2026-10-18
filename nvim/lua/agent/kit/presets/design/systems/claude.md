<!-- name: Claude -->
<!-- desc: warm conversational AI UI: cream background, terracotta accent, serif headings, calm and content-first -->

# DESIGN.md: Claude

The look of Anthropic's Claude: a warm, paper-like chat surface, a terracotta/clay accent, generous whitespace, and a calm
tone that keeps the conversation readable. Source: Claude's web UI (claude.ai); values are from the product and marked
"(approx.)" where they vary between versions or themes.

## Principles

- **Content first**: the conversation is the product; chrome (sidebars, toolbars) stays quiet and recedes.
- **Warm and calm**: cream backgrounds and soft grays instead of pure white and black; nothing feels clinical.
- **Readable prose**: long-form answers are the core artifact; typography and line length serve reading.
- **Trust and clarity**: actions are explicit, destructive ones are clearly marked, and uncertainty is stated, not hidden.
- **Progressive disclosure**: advanced options (model, tools, settings) live behind one click, not in the main flow.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FAF9F5` (approx.) | `#1F1F1E` (approx.) | App / chat background |
| `surface` | `#FFFFFF` (approx.) | `#2A2A28` (approx.) | Cards, code blocks, popovers |
| `surface-muted` | `#F0EEE6` (approx.) | `#333331` (approx.) | Sidebars, secondary panels |
| `text` | `#1F1F1E` (approx.) | `#F0EEE6` (approx.) | Body text, headings |
| `text-muted` | `rgba(31,31,30,0.65)` (approx.) | `rgba(240,238,230,0.65)` (approx.) | Secondary text, metadata |
| `text-faint` | `rgba(31,31,30,0.45)` (approx.) | `rgba(240,238,230,0.45)` (approx.) | Placeholders, hints |
| `border` | `rgba(31,31,30,0.10)` (approx.) | `rgba(240,238,230,0.10)` (approx.) | 1px separators |
| `accent` | `#D97757` (approx.) | `#D97757` (approx.) | Primary buttons, links, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#3D8B6E` (approx.) | `#3D8B6E` (approx.) | Success states |
| `warning` | `#B8860B` (approx.) | `#B8860B` (approx.) | Warnings |
| `danger` | `#C0392B` (approx.) | `#C0392B` (approx.) | Destructive actions |

- Accent is a warm terracotta/clay; it is used sparingly for primary actions and focus, never for large surfaces.
- Code blocks use a slightly darker surface in light mode and a slightly lighter one in dark mode for separation.

## Typography

Fonts: a serif for headings and display text (approx. Tiempos / Georgia family), a sans-serif for UI and body (approx.
Inter / system UI), and a monospace for code (approx. JetBrains Mono / system mono). (approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Display | 32–48px / 1.15 | 500–600 | Marketing and empty-state headings (approx.) |
| Heading | 20–24px / 1.25 | 600 | Section and panel titles (approx.) |
| Body | 16px / 1.6 | 400 | Conversation text, long-form answers (approx.) |
| UI | 14px / 1.5 | 400–500 | Sidebar rows, buttons, inputs (approx.) |
| Small | 12–13px / 1.4 | 400 | Metadata, timestamps, hints (approx.) |
| Code | 13–14px / 1.5 | 400 | Code blocks and inline code (approx.) |

- Long-form answers are constrained to a readable measure (~65–75 characters) and use generous line height.
- Headings use slight negative tracking at large sizes; body text uses default tracking.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16, 24, 32, 48 (approx.).
- Conversation column is centered with a max width (~720–768px) and comfortable side margins.
- Sidebar ~260px on desktop; collapses to a drawer on narrow screens.
- Composer is pinned at the bottom with a rounded input area and send button.

## Shape and elevation

- Radius: 8px (buttons, inputs), 12px (cards, code blocks), 16px (modals, popovers) (approx.).
- Borders: 1px, low contrast; surfaces separate mostly by lightness steps and subtle borders, not shadows.
- Elevation for floating layers only: a soft large shadow plus a 1px border on menus, popovers and modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 100–150ms (approx.) |
| duration-default | 150–250ms (approx.) |
| easing | ease-out (approx.) |

- Streaming text appears progressively without layout jumps; auto-scroll is smooth and pauses on user scroll.
- Hover and state changes are subtle; menus fade/slide in quickly; nothing animates longer than ~300ms.
- Reduced motion: no slides, fades only.

## Components

- **Conversation**: alternating user and assistant turns; assistant answers render as Markdown with code blocks, lists and tables.
- **Composer**: rounded multi-line input with a send button, attachment and tools entry points, and a stop button while streaming.
- **Sidebar**: conversation list grouped by recency, search, and a new-chat action; collapsible.
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
- Use the accent sparingly (primary actions, focus, links); keep surfaces warm and low-contrast.
- Prefer subtle borders and lightness steps over shadows; floating layers are the only elevated surfaces.
- Every new action is keyboard reachable and shown in its tooltip/menu row.
filePath: /home/sazar/Documents/my-nvim-setup/nvim/lua/agent/kit/presets/design/systems/claude.md