<!-- name: Page with its route -->
<!-- desc: a page/route in the project's framework, its data loading, its states and a test -->
<!-- for: ui -->
<!-- input: name | Name of the page (e.g. Account, Order history) -->
<!-- input: path | Its URL path and what it shows (e.g. /account: the user's profile and plan) -->

# Recipe: the {{name}} page

Route and content: {{path}}.

## Make

- The page in the router or file-based routing the framework uses (Next.js `app/`, SvelteKit `routes/`, Nuxt `pages/`, React Router, Astro `pages/`), with its title and meta.
- Its data: loaded the way the project loads data (server components, loaders, `load` functions, a query hook), with loading, empty and error states.
- A link to it from the navigation where it belongs.

## Rules

- Layout, spacing and colors from DESIGN.md's tokens; responsive at its breakpoints.
- Errors show what happened and what to do; no blank page.
- Follow the existing pages: layout component, data helpers, naming.

## Tests

- The page renders with its data, empty and error (mocked at the network or data layer the project mocks).
