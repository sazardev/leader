<!-- name: Ant Design -->
<!-- desc: Ant Group's enterprise system: seed/map/alias tokens, 14px base, 4px unit, 24-column grid -->

# DESIGN.md: Ant Design

Ant Design v5, the enterprise design system from Ant Group, built for dense data-heavy back-office products. Source of truth:
ant.design (Design Values, Global Styles, Customize Theme). Every value comes from the **token system**: seed tokens →
map tokens (derived by an algorithm) → alias tokens → component tokens. Components never read raw values.

## Principles

- **Natural**: interfaces follow how people already think and work; behaviour is predictable, not clever.
- **Certain**: consistent rules and components reduce decisions; the same thing always looks and behaves the same.
- **Meaningful**: every element serves the user's goal; clear feedback for every action, no decoration for its own sake.
- **Growing**: the system and the product grow together; extend through tokens and composition, not one-off overrides.
- **Efficiency in density**: back-office users scan and act on lots of data; compact, aligned, readable over spacious.

## Color

Seed tokens (default algorithm). Brand customization changes the seed; the algorithm derives the 10-step palettes.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `colorPrimary` | `#1677FF` | `#1668DC` | Primary buttons, links, active states |
| `colorSuccess` | `#52C41A` | `#49AA19` | Success status |
| `colorWarning` | `#FAAD14` | `#D89614` | Warning status |
| `colorError` | `#FF4D4F` | `#DC4446` | Errors, destructive actions |
| `colorInfo` | `#1677FF` | `#1668DC` | Informational status |
| `colorLink` | `#1677FF` | `#1668DC` | Text links |
| `colorText` | `rgba(0,0,0,0.88)` | `rgba(255,255,255,0.85)` | Main text |
| `colorTextSecondary` | `rgba(0,0,0,0.65)` | `rgba(255,255,255,0.65)` | Secondary text |
| `colorTextTertiary` | `rgba(0,0,0,0.45)` | `rgba(255,255,255,0.45)` | Hints, captions |
| `colorTextQuaternary` | `rgba(0,0,0,0.25)` | `rgba(255,255,255,0.25)` | Disabled text, placeholders |
| `colorBorder` | `#D9D9D9` | `#424242` | Input and control borders |
| `colorBorderSecondary` | `#F0F0F0` | `#303030` | Dividers, table lines |
| `colorBgContainer` | `#FFFFFF` | `#141414` | Cards, inputs, tables |
| `colorBgElevated` | `#FFFFFF` | `#1F1F1F` | Dropdowns, popovers, modals |
| `colorBgLayout` | `#F5F5F5` | `#000000` | Page background behind containers |
| `colorFillSecondary` | `rgba(0,0,0,0.06)` | `rgba(255,255,255,0.12)` | Hover fills, tags |

- Dark values are what `theme.darkAlgorithm` derives from the same seeds (approx.: they come from the algorithm, not a fixed table).
- Each seed expands into a 10-step palette (`blue-1` … `blue-10`, primary = step 6); use `colorPrimaryBg`, `colorPrimaryHover`, `colorPrimaryActive` instead of picking steps by hand.
- Status colors always come with an icon or text (Alert, Tag, Badge, Result), never color alone.

## Typography

Font: the system stack (`-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, 'Noto Sans', sans-serif`, plus emoji fonts). `fontSize` seed = 14.

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| h1 (`fontSizeHeading1`) | 38 / 46 | 600 | Page hero titles (rare) |
| h2 (`fontSizeHeading2`) | 30 / 38 | 600 | Page titles |
| h3 (`fontSizeHeading3`) | 24 / 32 | 600 | Section titles |
| h4 (`fontSizeHeading4`) | 20 / 28 | 600 | Card titles |
| h5 (`fontSizeHeading5`) | 16 / 24 | 600 | Group titles |
| large (`fontSizeLG`) | 16 / 24 | 400 | Emphasized body |
| base (`fontSize`) | 14 / 22 | 400 | Body and component text |
| small (`fontSizeSM`) | 12 / 20 | 400 | Captions, table meta |

- Base line height 1.5714 (22/14). Strong text is weight 600 (`fontWeightStrong`).
- Numbers in tables and statistics use tabular figures (`font-variant-numeric: tabular-nums`) and right alignment.

## Spacing and layout

- Size unit 4px, size step 4: `sizeXXS` 4, `sizeXS` 8, `sizeSM` 12, `size` 16, `sizeMD` 20, `sizeLG` 24, `sizeXL` 32, `sizeXXL` 48.
- Padding/margin tokens: `paddingXS` 8, `paddingSM` 12, `padding` 16, `paddingLG` 24; `marginXS` 8 … `marginLG` 24.
- 24-column grid (`Row`/`Col`), gutters 8/16/24/32. Breakpoints: xs < 576, sm ≥ 576, md ≥ 768, lg ≥ 992, xl ≥ 1200, xxl ≥ 1600.
- Layout: `Layout` with `Sider` (200px, collapsed 80px) + `Header` (64px) + `Content`; content padding 24px.
- Controls: `controlHeight` 32 (SM 24, LG 40). Align labels and controls on one grid; forms are vertical on narrow screens, horizontal with fixed label column on wide ones.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `borderRadiusXS` | 2px | Tags inside dense rows |
| `borderRadiusSM` | 4px | Small controls, checkboxes |
| `borderRadius` | 6px | Buttons, inputs, selects |
| `borderRadiusLG` | 8px | Cards, modals, popovers |
| `lineWidth` | 1px | Borders (`lineType: solid`) |

- Elevation is borders first; shadows only for floating layers: `boxShadow` (popovers, dropdowns, modals), `boxShadowSecondary`, `boxShadowTertiary` (cards on hover).
- Default `boxShadow`: `0 6px 16px 0 rgba(0,0,0,0.08), 0 3px 6px -4px rgba(0,0,0,0.12), 0 9px 28px 8px rgba(0,0,0,0.05)`.

## Motion

| Token | Value |
| --- | --- |
| `motionDurationFast` | 0.1s |
| `motionDurationMid` | 0.2s |
| `motionDurationSlow` | 0.3s |
| `motionEaseInOut` | `cubic-bezier(0.645, 0.045, 0.355, 1)` |
| `motionEaseOut` | `cubic-bezier(0.215, 0.61, 0.355, 1)` |
| `motionEaseIn` | `cubic-bezier(0.55, 0.055, 0.675, 0.19)` |
| `motionEaseOutBack` | `cubic-bezier(0.12, 0.4, 0.29, 1.46)` |
| `motionEaseInOutCirc` | `cubic-bezier(0.78, 0.14, 0.15, 0.86)` |

- Hover/active color changes: fast; dropdowns, collapses, tabs: mid; drawers and modals: slow.
- Motion is functional (where did it come from, what changed); no decorative loops. Honour `prefers-reduced-motion` (`theme.token.motion = false` disables it).

## Components

- **Buttons**: one `type="primary"` per area; `default` for secondary, `text`/`link` for tertiary, `danger` for destructive. Order: primary on the right in footers, on the left in page-level toolbars.
- **Forms**: `Form` with `rules` for validation; required marks, inline errors under the field, submit disabled only while submitting (`loading`).
- **Tables**: the core of the product. Fixed header for long lists, sortable/filterable columns, row actions in the last column (max 2 visible + `Dropdown` "More"), pagination 10/20/50, empty state via `Empty`.
- **Feedback**: `message` for light confirmations, `notification` for async results, `Modal.confirm` for destructive confirmation, `Alert` inline for page-level status, `Result` for full outcomes.
- **Navigation**: `Menu` in the `Sider` (max 2 levels), `Breadcrumb` for deep pages, `Tabs` for sibling views.
- **States**: `Skeleton` for first load of content, `Spin` for in-place refresh, `Empty` with an action for empty lists, `Result status="error"` with retry.

## Accessibility

- Text contrast ≥ 4.5:1; check custom seeds, the default `colorTextTertiary` is for non-essential text only.
- Every control has a visible label (Form.Item `label`), icon-only buttons get `aria-label` and a `Tooltip`.
- Keyboard: every overlay is reachable and closable with Esc; focus returns to the trigger; tables with row actions are tab-navigable.
- Focus outline visible (`controlOutline`, `controlOutlineWidth` 2px); never remove it.
- Never color alone for status: `Tag`/`Badge` with text, `Alert` with icon.

## Rules for agents

- Theme only through `ConfigProvider theme={{ token: {...}, algorithm: [...], components: {...} }}`; switch dark with `theme.darkAlgorithm`, compact with `theme.compactAlgorithm`.
- In custom components read tokens with `theme.useToken()` (or `antd-style`/CSS variables mode `cssVar: true`); never hardcode hex, px radius or shadows.
- Use the Ant component for the job before writing a custom one (Table, Form, Descriptions, Statistic, Upload…); compose, do not override internals with deep CSS selectors.
- Per-component tweaks go in `components.<Name>` tokens, not global CSS.
- Forms use `Form` + `Form.Item` with `rules`; never manage validation state by hand.
- Layout with `Row`/`Col`/`Flex`/`Space` and the size tokens; no magic margins.
- Every list/table screen implements loading, empty, error and pagination.
