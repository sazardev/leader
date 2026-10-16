<!-- name: Salesforce Lightning -->
<!-- desc: Salesforce Lightning Design System: SLDS styling hooks, Salesforce Sans, 4px spacing, enterprise density -->

# DESIGN.md: Salesforce Lightning

The Salesforce Lightning Design System (SLDS). Source of truth: lightningdesignsystem.com. Values come from **styling
hooks** (CSS custom properties `--slds-g-*` global hooks, `--slds-c-*` component hooks) and design tokens; markup follows
the SLDS BEM classes (`slds-button`, `slds-card`).

## Principles

- **Clarity**: eliminate ambiguity; people see, understand and act with confidence.
- **Efficiency**: streamline workflows for people who live in the product all day.
- **Consistency**: the same solution for the same problem, across clouds.
- **Beauty**: craft and respect for the user's time.
- **Hooks, not overrides**: customize through styling hooks, never by overriding SLDS classes.

## Color

| Token / hook | Light | Use |
| --- | --- | --- |
| Brand (`--slds-g-color-brand-base-50`) | `#0176D3` | Brand buttons, active states |
| Brand dark (`brand-base-30`) | `#014486` | Pressed brand |
| Text default | `#181818` | Body text |
| Text weak | `#444444` (approx.) | Secondary text |
| Text placeholder | `#747474` | Placeholders |
| Background | `#F3F3F3` | App background |
| Surface (`--slds-g-color-surface-1`) | `#FFFFFF` | Cards |
| Border (`--slds-g-color-border-1`) | `#C9C9C9` | Dividers, inputs |
| Error | `#BA0517` | Errors |
| Success | `#2E844A` | Success |
| Warning | `#DD7A01` | Warnings |
| Info / link | `#0B5CAB` | Links |
| Focus | `#0176D3` with `0 0 3px` shadow | Focus |

- Dark mode is limited in SLDS (SLDS 2 / Cosmos theme adds more) (approx.): plan light-first.
- Color hooks follow the 2-digit palette scale (`-10` darkest … `-95` lightest).

## Typography

Font: Salesforce Sans (fallback `-apple-system, "Segoe UI", Roboto, Arial`); base size 13px in older SLDS, 14px in SLDS 2 (approx.).

| Role (class) | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| `slds-text-heading_large` | 28 / 1.25 | 300 | Page title |
| `slds-text-heading_medium` | 20 / 1.25 | 300 | Section title |
| `slds-text-heading_small` | 16 / 1.25 | 400 | Card title |
| `slds-text-title_caps` | 12 / 1.25 | 400, uppercase | Labels |
| `slds-text-body_regular` | 13 / 1.5 | 400 | Body |
| `slds-text-body_small` | 12 / 1.5 | 400 | Metadata |

## Spacing and layout

- 4px scale (spacing tokens): xxx-small 2, xx-small 4, x-small 8, small 12, medium 16, large 24, x-large 32, xx-large 48.
- Grid: `slds-grid` flexbox with `slds-col` and `slds-size_1-of-2` style sizing; gutters `slds-gutters`.
- Breakpoints: small 480, medium 768, large 1024px.
- Record pages: header, two-column body (main + sidebar), related lists.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| Radius small | 0.125rem (2px) | Badges |
| Radius medium | 0.25rem (4px) | Buttons, inputs, cards |
| Radius large | 0.5rem (8px) | Modals (SLDS 2 rounder, approx.) |
| Radius circle | 50% | Avatars |
| Border | 1px `#C9C9C9` | Inputs, cards |

Elevation: card shadow `0 2px 2px rgba(0,0,0,0.1)`, dropdown `0 2px 3px rgba(0,0,0,0.16)`, modal backdrop `rgba(8,7,7,0.6)` (approx.).

## Motion

- Durations: instantly 0, immediately 50ms, promptly 100ms, quickly 200ms, slowly 400ms, paused 3.2s.
- Easing: standard ease-in-out; spinners and progress are the main animated components.
- Respect `prefers-reduced-motion`.

## Components

- **Buttons**: `slds-button_brand` (primary, one per region), `slds-button_neutral`, `slds-button_destructive`, `slds-button_outline-brand`; button groups for related actions.
- **Cards** (`slds-card`) for related content with header actions.
- **Data tables** (`lightning-datatable`): inline edit, sorting, row actions, infinite loading.
- **Forms**: `slds-form-element` label above, help text, error under the field; compound fields grouped.
- **Feedback**: toasts (top center), scoped notifications, illustrations for empty states.
- **Modals**: header, content, footer with Cancel then primary on the right.

## Accessibility

- SLDS components ship accessible markup and keyboard patterns: keep their ARIA.
- Text contrast 4.5:1; focus visible with the brand focus shadow.
- Targets ≥ 24px; touch views (mobile) ≥ 44px.
- Status always with text or an icon with an assistive label (`slds-assistive-text`).

## Rules for agents

- In Salesforce: use Lightning Web Components base components (`lightning-button`, `lightning-card`, `lightning-datatable`, `lightning-input`).
- Outside Salesforce: `@salesforce-ux/design-system` CSS and SLDS markup/BEM classes.
- Customize only through styling hooks (`--slds-c-button-brand-color-background`), never by overriding `.slds-*` classes.
- Spacing with SLDS utility classes (`slds-m-around_medium`, `slds-p-horizontal_small`), not custom margins.
- One brand button per region; destructive actions use `slds-button_destructive` and a confirmation modal.
