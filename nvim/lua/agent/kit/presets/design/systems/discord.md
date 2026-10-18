<!-- name: Discord -->
<!-- desc: dark chat UI: blurple accent, rounded bubbles, dense channels, playful but focused -->

# DESIGN.md: Discord

The look of Discord: a dark, dense chat interface with a blurple accent, rounded message bubbles, channel sidebars and a
playful but focused tone. Source: Discord's product UI (discord.com); values are from the product and marked "(approx.)"
where they vary between versions or themes.

## Principles

- **Community first**: channels, members and voice are central; chrome stays out of the way.
- **Dense but readable**: lots of messages per screen, with clear author and timestamp hierarchy.
- **Playful but focused**: rounded corners and a bright accent, without sacrificing clarity.
- **Real-time**: messages, presence and voice update instantly.
- **Customizable**: themes, avatars and roles let communities express identity.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#313338` (approx.) | App background |
| `surface` | `#F2F3F5` (approx.) | `#2B2D31` (approx.) | Sidebars, panels |
| `surface-raised` | `#FFFFFF` (approx.) | `#383A40` (approx.) | Menus, popovers, modals |
| `text` | `#060607` (approx.) | `#F2F3F5` (approx.) | Body text, headings |
| `text-muted` | `#4E5058` (approx.) | `#B5BAC1` (approx.) | Secondary text, metadata |
| `text-faint` | `#747F8D` (approx.) | `#949BA4` (approx.) | Placeholders, hints |
| `border` | `#E3E5E8` (approx.) | `#3F4148` (approx.) | 1px separators |
| `accent` | `#5865F2` | `#5865F2` | Primary buttons, links, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#23A559` (approx.) | `#23A559` (approx.) | Success states, online |
| `warning` | `#F0B232` (approx.) | `#F0B232` (approx.) | Warnings |
| `danger` | `#F23F43` (approx.) | `#F23F43` (approx.) | Destructive actions, errors |

- Accent is a Discord blurple used for primary actions, links and focus; large surfaces stay dark gray.
- Status colors (online, idle, dnd, offline) are distinct and always paired with icons.

## Typography

Fonts: system sans-serif (approx. gg sans / platform UI) for UI text, and a monospace for code (approx. system mono).
(approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Heading | 16–20px / 1.2 | 700 | Channel and server titles (approx.) |
| Body | 16px / 1.375 | 400 | Message text (approx.) |
| UI | 14px / 1.3 | 400–500 | Sidebar rows, buttons, inputs (approx.) |
| Small | 12px / 1.3 | 400–500 | Timestamps, metadata, hints (approx.) |
| Code | 13–14px / 1.4 | 400 | Code blocks and inline code (approx.) |

- Message text is compact with modest line height for density.
- Timestamps are muted and appear on hover or in compact mode.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16 (approx.).
- Server list ~72px, channel sidebar ~240px, member list ~240px, chat fills the rest.
- Messages use 4px vertical spacing; compact mode reduces it further.
- Composer is pinned at the bottom with a rounded input area.

## Shape and elevation

- Radius: 4px (buttons, inputs), 8px (cards, code blocks), 12–16px (modals, popovers) (approx.).
- Borders: 1px, low contrast; surfaces separate by lightness steps and borders.
- Elevation for floating layers only: a soft shadow plus a 1px border on menus, popovers and modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 100–150ms (approx.) |
| duration-default | 150–250ms (approx.) |
| easing | ease-out (approx.) |

- Messages and presence update instantly; auto-scroll pauses on user scroll.
- Hover and state changes are snappy; menus fade/slide in quickly.
- Reduced motion: no slides, fades only.

## Components

- **Servers**: vertical icon list with badges, tooltips and a home button.
- **Channels**: grouped list with category headers, unread indicators and hover actions.
- **Messages**: avatar, author, timestamp and content; reactions, replies and thread links.
- **Composer**: rounded multi-line input with formatting, attachments and send button.
- **Voice**: channel list with speaking indicators and a bottom voice panel.
- **Members**: list with status, roles and hover cards.
- **Modals**: centered cards with clear primary and secondary actions.

## Accessibility

- Text and `text-muted` meet 4.5:1 on their surfaces in both themes.
- Focus visible on every interactive element (accent ring) for keyboard users.
- Keyboard navigation covers channels, messages and composer; shortcuts are discoverable.
- Color never alone for status; icons and labels accompany color.
- Targets ≥ 24px on desktop, 44px on touch.

## Rules for agents

- Implement tokens as CSS variables; components never hardcode colors; support light and dark themes from the same tokens.
- Keep messages dense but readable; use clear author and timestamp hierarchy.
- Use the accent sparingly (primary actions, focus, links); keep surfaces dark and neutral.
- Prefer subtle borders and lightness steps over shadows; floating layers are the only elevated surfaces.
- Every new action is keyboard reachable and shown in its tooltip/menu row.
- Respect user theme and accessibility settings.
filePath: /home/sazar/Documents/my-nvim-setup/nvim/lua/agent/kit/presets/design/systems/discord.md