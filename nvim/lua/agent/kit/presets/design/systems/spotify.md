<!-- name: Spotify -->
<!-- desc: dark music UI: black surfaces, green accent, bold imagery, immersive cards -->

# DESIGN.md: Spotify

The look of Spotify: an immersive, dark music interface with black surfaces, a green accent, bold imagery and rounded
cards that put content and playback first. Source: Spotify's product UI (open.spotify.com, desktop app); values are from
the product and marked "(approx.)" where they vary between versions or themes.

## Principles

- **Content first**: album art and playback dominate; chrome recedes to black.
- **Immersive**: dark surfaces and bold imagery create a focused listening experience.
- **Fast and fluid**: playback and navigation are instant; nothing blocks listening.
- **Personalized**: recommendations and playlists adapt to the user.
- **Accessible**: controls and text remain legible on varied imagery.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#121212` | App background |
| `surface` | `#F6F6F6` (approx.) | `#181818` (approx.) | Cards, panels, sidebars |
| `surface-raised` | `#FFFFFF` (approx.) | `#282828` (approx.) | Menus, popovers, modals |
| `text` | `#000000` | `#FFFFFF` | Body text, headings |
| `text-muted` | `#535353` (approx.) | `#B3B3B3` (approx.) | Secondary text, metadata |
| `text-faint` | `#A7A7A7` (approx.) | `#7F7F7F` (approx.) | Placeholders, hints |
| `border` | `#E6E6E6` (approx.) | `#2A2A2A` (approx.) | 1px separators |
| `accent` | `#1DB954` | `#1DB954` | Primary buttons, play, focus |
| `on-accent` | `#000000` | `#000000` | Text on accent |
| `success` | `#1DB954` (approx.) | `#1DB954` (approx.) | Success states |
| `warning` | `#FFC107` (approx.) | `#FFC107` (approx.) | Warnings |
| `danger` | `#E91429` (approx.) | `#E91429` (approx.) | Destructive actions, errors |

- Accent is a Spotify green used for play buttons, primary actions and focus; large surfaces stay black.
- Album art provides color; UI chrome stays neutral to avoid clashing.

## Typography

Fonts: system sans-serif (approx. Spotify Circular / platform UI) for UI text, and a monospace for code (approx. system mono).
(approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Display | 32–48px / 1.1 | 700–800 | Hero and playlist titles (approx.) |
| Heading | 20–24px / 1.2 | 700 | Section titles (approx.) |
| Body | 16px / 1.5 | 400 | Descriptions and long-form text (approx.) |
| UI | 14px / 1.3 | 400–600 | List rows, buttons, inputs (approx.) |
| Small | 12px / 1.3 | 400–500 | Metadata, hints (approx.) |
| Code | 13–14px / 1.5 | 400 | Code blocks (approx.) |

- Headings are bold and tight; body text uses default tracking.
- Tabular figures for durations and counts.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16, 24, 32 (approx.).
- Left sidebar ~240px, main content fills the rest, bottom player bar ~90px.
- Cards and rows use 8–16px gaps; grids adapt to window width.
- Playback controls are always visible in the bottom bar.

## Shape and elevation

- Radius: 4px (buttons, inputs), 8px (cards, rows), 16–24px (modals, popovers) (approx.).
- Borders: 1px, low contrast; surfaces separate by lightness steps and borders.
- Elevation for floating layers only: a soft shadow plus a 1px border on menus, popovers and modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 100–150ms (approx.) |
| duration-default | 150–250ms (approx.) |
| easing | ease-out (approx.) |

- Playback and navigation are instant; menus fade/slide in quickly.
- Hover and state changes are snappy; nothing animates longer than ~300ms.
- Reduced motion: no slides, fades only.

## Components

- **Sidebar**: home, search, library, playlists and create playlist action.
- **Main view**: hero, horizontal card rows, and dense track lists.
- **Cards**: album/playlist art with title and subtitle; hover shows play button.
- **Track list**: rows with number, title, artist, album, duration and actions.
- **Player bar**: track info, play/pause, skip, seek bar, volume and device picker.
- **Search**: large input with filters and result sections.
- **Modals**: centered cards for login, playlist creation and settings.

## Accessibility

- Text and `text-muted` meet 4.5:1 on their surfaces in both themes.
- Focus visible on every interactive element (accent ring) for keyboard users.
- Keyboard navigation covers playback and lists; shortcuts are discoverable.
- Color never alone for status; icons and labels accompany color.
- Targets ≥ 24px on desktop, 44px on touch.

## Rules for agents

- Implement tokens as CSS variables; components never hardcode colors; support light and dark themes from the same tokens.
- Keep playback controls always visible and accessible.
- Use bold imagery but keep text legible on varied backgrounds.
- Use the accent sparingly (play, primary actions, focus); keep surfaces black and neutral.
- Prefer subtle borders and lightness steps over shadows; floating layers are the only elevated surfaces.
- Every new action is keyboard reachable and shown in its tooltip/menu row.
filePath: /home/sazar/Documents/my-nvim-setup/nvim/lua/agent/kit/presets/design/systems/spotify.md