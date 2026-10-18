<!-- name: ChatGPT -->
<!-- desc: clean chat UI: light/dark surfaces, green accent, rounded bubbles, simple and accessible -->

# DESIGN.md: ChatGPT

The look of OpenAI's ChatGPT: a clean, minimal chat surface with light and dark themes, a green accent, rounded message
bubbles, and a focus on readability and accessibility. Source: ChatGPT's web UI (chatgpt.com); values are from the product
and marked "(approx.)" where they vary between versions or themes.

## Principles

- **Simple and direct**: the conversation is central; navigation and settings stay out of the way.
- **Readable**: long-form answers use comfortable measure and line height; code is clearly separated.
- **Accessible**: strong contrast, keyboard support, and clear focus states in both themes.
- **Consistent**: one accent color and a small set of surfaces across the whole product.
- **Progressive disclosure**: model and tool options are one click away, not in the main flow.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#212121` (approx.) | App / chat background |
| `surface` | `#F7F7F8` (approx.) | `#2F2F2F` (approx.) | Cards, code blocks, popovers |
| `surface-muted` | `#ECECEC` (approx.) | `#3A3A3A` (approx.) | Sidebars, secondary panels |
| `text` | `#0D0D0D` (approx.) | `#ECECEC` (approx.) | Body text, headings |
| `text-muted` | `#595959` (approx.) | `#A0A0A0` (approx.) | Secondary text, metadata |
| `text-faint` | `#8E8E8E` (approx.) | `#6E6E6E` (approx.) | Placeholders, hints |
| `border` | `#E5E5E5` (approx.) | `#424242` (approx.) | 1px separators |
| `accent` | `#10A37F` | `#10A37F` | Primary buttons, links, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#10A37F` (approx.) | `#10A37F` (approx.) | Success states |
| `warning` | `#F5A623` (approx.) | `#F5A623` (approx.) | Warnings |
| `danger` | `#EF4146` (approx.) | `#EF4146` (approx.) | Destructive actions |

- Accent is a calm green used for primary actions, links and focus; large surfaces stay neutral.
- User and assistant messages are distinguished by surface and alignment, not by strong color.

## Typography

Fonts: system sans-serif (approx. Söhne / Inter / platform UI) for all UI text, and a monospace for code (approx. system mono).
(approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Display | 28–36px / 1.15 | 600 | Marketing and empty-state headings (approx.) |
| Heading | 18–22px / 1.25 | 600 | Section and panel titles (approx.) |
| Body | 16px / 1.6 | 400 | Conversation text, long-form answers (approx.) |
| UI | 14px / 1.5 | 400–500 | Sidebar rows, buttons, inputs (approx.) |
| Small | 12–13px / 1.4 | 400 | Metadata, timestamps, hints (approx.) |
| Code | 13–14px / 1.5 | 400 | Code blocks and inline code (approx.) |

- Long-form answers are constrained to a readable measure and use generous line height.
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
- Use the accent sparingly (primary actions, focus, links); keep surfaces neutral and clean.
- Prefer subtle borders and lightness steps over shadows; floating layers are the only elevated surfaces.
- Every new action is keyboard reachable and shown in its tooltip/menu row.
filePath: /home/sazar/Documents/my-nvim-setup/nvim/lua/agent/kit/presets/design/systems/chatgpt.md