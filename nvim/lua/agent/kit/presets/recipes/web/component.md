<!-- name: UI component -->
<!-- desc: a component in the project's framework, its styles from DESIGN.md's tokens, its states and a test -->
<!-- for: ui -->
<!-- input: name | Name of the component (e.g. Price tag, User menu) -->
<!-- input: does | What it shows and how it behaves (one sentence) -->

# Recipe: the {{name_pascal}} component

{{does}}

## Make

- `{{name_pascal}}` in the framework STACK.md names (React, Vue, Svelte, Solid, Lit…), in the components folder of its layout (e.g. `src/components/{{name_kebab}}/`), typed props/inputs with defaults.
- Its styles with the project's styling approach (CSS Modules `{{name_kebab}}.module.css`, Tailwind classes, plain CSS next to it): DESIGN.md's tokens only, every interactive state (hover, focus-visible, active, disabled).
- The states the sentence implies: empty, loading, error, long text.
- Used once where the user meets it, if that place exists.

## Rules

- Accessible: a real button/link/input for what is interactive, labels for icons, keyboard reachable, focus visible, targets 24 px or more.
- No data fetching inside a presentational component: data comes in through props.
- Follow the existing components: file shape, naming, how they export.

## Tests

- With the project's test tools (Vitest/Jest + Testing Library, or the framework's): it renders its main state, each other state, and the interaction calls what it must.
