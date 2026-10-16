<!-- name: shadcn/ui -->
<!-- desc: Radix + Tailwind v4 components you own: oklch CSS variables, neutral base, 0.625rem radius, Lucide icons -->

# DESIGN.md: shadcn/ui

shadcn/ui: accessible components built on Radix UI primitives and Tailwind CSS, copied into the project (not installed as a
dependency). Source of truth: ui.shadcn.com. The look is defined by a small set of **semantic CSS variables** (Tailwind v4,
oklch) consumed as Tailwind utilities (`bg-background`, `text-muted-foreground`); a theme is a new set of values, not new classes.

## Principles

- **You own the code**: components live in `components/ui/` and are edited like any project code; consistency comes from the variables and variants, not from a package.
- **Neutral and quiet**: grayscale UI, one primary, color reserved for meaning (destructive, charts).
- **Composition over configuration**: small parts (`Card`, `CardHeader`, `CardContent`…) composed, not giant prop APIs.
- **Accessible by construction**: Radix primitives handle focus, keyboard and ARIA; styling never breaks them.
- **Pairs, always**: every surface variable has a `-foreground` partner used on top of it.

## Color

Neutral base color, Tailwind v4 defaults (`globals.css`).

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `--background` | `oklch(1 0 0)` | `oklch(0.145 0 0)` | Page background |
| `--foreground` | `oklch(0.145 0 0)` | `oklch(0.985 0 0)` | Body text |
| `--card` / `--popover` | `oklch(1 0 0)` | `oklch(0.205 0 0)` | Cards, popovers |
| `--primary` | `oklch(0.205 0 0)` | `oklch(0.922 0 0)` | Default buttons, key actions |
| `--primary-foreground` | `oklch(0.985 0 0)` | `oklch(0.205 0 0)` | Text on primary |
| `--secondary` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | Secondary buttons |
| `--muted` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | Muted backgrounds |
| `--muted-foreground` | `oklch(0.556 0 0)` | `oklch(0.708 0 0)` | Secondary text, descriptions |
| `--accent` | `oklch(0.97 0 0)` | `oklch(0.269 0 0)` | Hover/active rows and items |
| `--destructive` | `oklch(0.577 0.245 27.325)` | `oklch(0.704 0.191 22.216)` | Destructive actions, errors |
| `--border` | `oklch(0.922 0 0)` | `oklch(1 0 0 / 10%)` | Borders, dividers |
| `--input` | `oklch(0.922 0 0)` | `oklch(1 0 0 / 15%)` | Input borders |
| `--ring` | `oklch(0.708 0 0)` | `oklch(0.556 0 0)` | Focus ring |
| `--chart-1…5` | `oklch(0.646 0.222 41.116)` … | `oklch(0.488 0.243 264.376)` … | Chart series only |
| `--sidebar-*` | `--sidebar`, `-foreground`, `-primary`, `-accent`, `-border`, `-ring` | | The sidebar's own palette |

- Success/warning/info are not in the base set: add `--success`/`--success-foreground` (etc.) to `:root` and `.dark`, and register them in `@theme inline`.
- Other base colors (stone, zinc, gray, slate) only change the neutral hue; pick one and never mix.

## Typography

- Font: Geist Sans + Geist Mono (Next.js default via `next/font`), or Inter; set as `--font-sans` / `--font-mono` in `@theme`.
- Tailwind scale: `text-xs` 12/16, `text-sm` 14/20 (default UI text), `text-base` 16/24 (reading), `text-lg` 18/28, `text-xl` 20/28, `text-2xl` 24/32, `text-3xl` 30/36, `text-4xl` 36/40.
- Weights: 400 body, 500 labels/buttons (`font-medium`), 600 titles (`font-semibold`).
- Headings: `scroll-m-20 text-4xl font-extrabold tracking-tight` (h1), `text-3xl font-semibold tracking-tight` (h2), `text-2xl` (h3) per the typography page.
- `tabular-nums` for numbers in tables and stats.

## Spacing and layout

- Tailwind's 4px scale (`--spacing: 0.25rem`): `1` 4, `2` 8, `3` 12, `4` 16, `6` 24, `8` 32, `12` 48, `16` 64.
- Component internals: `gap-2`/`p-4`/`p-6` (cards use `py-6 px-6`, gaps `gap-6`).
- Breakpoints: `sm` 640, `md` 768, `lg` 1024, `xl` 1280, `2xl` 1536; container queries (`@container`) for components.
- Control heights: buttons/inputs `h-9` (36px) default, `h-8` small, `h-10` large.

## Shape and elevation

- `--radius: 0.625rem` (10px); derived in `@theme inline`: `--radius-sm: calc(var(--radius) - 4px)` (6), `--radius-md: calc(var(--radius) - 2px)` (8), `--radius-lg: var(--radius)` (10), `--radius-xl: calc(var(--radius) + 4px)` (14).
- Buttons/inputs `rounded-md`, cards `rounded-xl`, badges `rounded-md`, avatars `rounded-full`.
- Borders do the separation (`border` with `--border`); shadows are light: `shadow-xs` on inputs/buttons, `shadow-sm` on cards, `shadow-md`/`shadow-lg` on popovers, menus, dialogs.

## Motion

- Animations via `tw-animate-css` (Tailwind v4; replaces `tailwindcss-animate`): `animate-in fade-in-0 zoom-in-95`, `slide-in-from-top-2`, `data-[state=closed]:animate-out fade-out-0 zoom-out-95`.
- Durations: Tailwind `duration-150` (hover, color), `duration-200` (popovers, menus), `duration-300` (sheets/drawers, approx. defaults per component).
- Easing: `ease-out` to enter, `ease-in` to exit, `ease-in-out` for movement; `transition-[color,box-shadow]` on controls.
- Respect `motion-reduce:`: remove zoom/slide, keep opacity.

## Components

- **Button** variants (cva): `default`, `secondary`, `outline`, `ghost`, `link`, `destructive`; sizes `sm`, `default`, `lg`, `icon`. One `default` button per view.
- **Forms**: `Form` (react-hook-form + zod) with `FormField`/`FormItem`/`FormLabel`/`FormControl`/`FormMessage`; errors under the field with `text-destructive`.
- **Data**: `Table` for static data, TanStack Table recipe (`DataTable`) for sort/filter/pagination.
- **Navigation**: `Sidebar` block for apps, `NavigationMenu` for sites, `Tabs`, `Breadcrumb`, `Command` (⌘K) for search/actions.
- **Overlays**: `Dialog` for decisions, `Sheet`/`Drawer` for side tasks and mobile, `Popover`/`DropdownMenu` for small choices, `AlertDialog` for destructive confirmation.
- **Feedback**: `Sonner` toasts, `Alert` inline, `Skeleton` for loading, empty states with one action.

## Accessibility

- Radix provides focus management, keyboard interaction and ARIA; never replace a primitive's trigger with a non-button element.
- Focus ring: `focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:border-ring`; invalid fields `aria-invalid:ring-destructive/20 aria-invalid:border-destructive`.
- Text contrast ≥ 4.5:1; check `muted-foreground` on `muted` and every custom color pair.
- Icon-only buttons get `<span className="sr-only">` text or `aria-label`; dialogs always have `DialogTitle` (visually hidden if needed).
- Targets ≥ 24×24px; prefer `h-9`+ controls and larger on touch.

## Rules for agents

- Add components with the CLI (`npx shadcn@latest add button`), then edit them in `components/ui/`; never install a second component library.
- Use semantic utilities only (`bg-primary text-primary-foreground`, `border-border`, `text-muted-foreground`); never raw Tailwind colors (`bg-zinc-900`) or hex in components.
- New variants go into the component's `cva` definition, not as one-off className overrides; merge classes with `cn()`.
- New tokens go into `:root`, `.dark` and `@theme inline` together.
- Icons from `lucide-react`, `size-4` inside buttons and menus.
- Dark mode via the `.dark` class (`next-themes`); test every screen in both themes.
- Keep `components/ui/` generic: product-specific compositions live in `components/<feature>/`.
