<!-- name: Astro content site -->
<!-- desc: Astro: content collections, MDX, islands only where needed, Tailwind, near-zero JS, static first -->

# STACK.md: Astro content site

## Summary

A content-first website (docs, blog, marketing, portfolio) on Astro. Pages are rendered to static HTML at build time and
ship zero JavaScript by default; interactivity is added as isolated islands that hydrate only when needed. Content is
Markdown/MDX in type-checked content collections, so a typo in front matter fails the build instead of the page.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`; fall back to 6.x if `astro check` lags) (`strict` Astro tsconfig) | Typed props and content |
| Framework | Astro 5 | Static by default, islands, content layer |
| Content | Content collections (`src/content.config.ts`) with Zod schemas + MDX (`@astrojs/mdx`) | Validated front matter |
| Islands | Preact or Svelte (one framework only) | Small runtime for the few interactive parts |
| Styling | Tailwind CSS 4 (`@tailwindcss/vite`) | Tokens in the theme |
| Images | `astro:assets` (`<Image />`, `<Picture />`) | Sizes, formats and lazy loading at build |
| SEO | `@astrojs/sitemap`, RSS (`@astrojs/rss`), per-page meta component | |
| Search | Pagefind (static index) | No server needed |
| Tests | Vitest (utilities) + Playwright (pages, links, a11y with `@axe-core/playwright`) | |
| Lint/format | ESLint (`eslint-plugin-astro`) + Prettier (`prettier-plugin-astro`) + `astro check` | |
| Deploy | Static hosting (any CDN); an adapter only if SSR is required | |
| Package manager | pnpm | |

## Project layout

```
src/
  content.config.ts                collections and their Zod schemas
  content/
    blog/2025-01-10-hello.mdx
    docs/getting-started.md
  pages/                           routes only
    index.astro
    blog/index.astro
    blog/[...slug].astro           getStaticPaths from the collection
    rss.xml.ts
  layouts/
    BaseLayout.astro               <html>, head, Seo, header, footer
    PostLayout.astro
  components/
    Seo.astro                      title, description, canonical, Open Graph
    Header.astro
    PostCard.astro
    islands/ThemeToggle.tsx        the only hydrated components live here
  lib/
    posts.ts                       queries over collections (sorting, drafts, tags)
    format-date.ts
  styles/global.css
public/                            files served as is (favicon, robots.txt)
tests/e2e/
```

Dependency direction: `pages → layouts → components → lib`; `lib` is plain TypeScript with no Astro components;
`components/islands` never import `.astro` files.

## Conventions

- One file = one responsibility: one component, one layout, one query helper.
- `.astro` components by default; an island only when the user interacts with it, with the laziest directive that works (`client:visible` > `client:idle` > `client:load`).
- Every collection entry is validated by its schema; drafts are filtered in `lib/posts.ts`, never in pages.
- Every page sets title, description and canonical URL through `Seo.astro`.
- Images go through `astro:assets` with width, height and `alt`; decorative images use `alt=""`.
- URLs are stable: renaming a slug requires a redirect in `astro.config.mjs`.
- New section = a collection + schema → query helper in `lib/` → page with `getStaticPaths` → layout/components.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` |
| Preview | `pnpm preview` |
| Type/content check | `pnpm astro check` |
| Sync content types | `pnpm astro sync` |
| Lint | `pnpm lint` |
| Format | `pnpm prettier --write .` |
| Tests | `pnpm vitest run && pnpm playwright test` |

## Testing

- `astro check` is the first test: content schemas and component props.
- Vitest for `lib/` helpers (sorting, filtering, formatting).
- Playwright on the built site: key pages render, no broken internal links, no axe violations, RSS and sitemap valid.
- Lighthouse CI budget on the home page and a content page.

## Quality gates

- `astro check` with zero errors, ESLint `--max-warnings 0`, Prettier clean.
- Lighthouse: performance ≥ 95, accessibility 100, SEO 100 on key pages.
- JavaScript budget: pages without islands ship 0 KB of JS; total island JS per page under 50 KB gzipped.

## Dependencies

- Astro built-ins first (`astro:assets`, content collections, `<ClientRouter />` view transitions).
- Allowed: the table above; anything else needs a reason in the PR.
- Do NOT use: a second UI framework for islands, client-side routing libraries, jQuery, analytics scripts that block rendering, external image CDNs when `astro:assets` is enough, Google Fonts links (self-host fonts).

## Rules for agents

- Never add a `client:*` directive unless the component needs interaction; prefer `client:visible`.
- Never render content without its collection schema; add fields to the schema first.
- Use `<Image />` from `astro:assets` for every content image, always with `alt`.
- Every new page uses a layout and the `Seo` component.
- Keep pages free of data logic: queries live in `lib/`.
- Do not introduce an SSR adapter unless a feature truly needs per-request rendering.
- Self-host fonts and assets; no third-party requests on page load without a reason.
- Changing a URL requires a redirect entry.
