<!-- name: Module with its tests -->
<!-- desc: one cohesive module where STACK.md's layout puts it, its public API and its unit tests (any stack) -->
<!-- for: all -->
<!-- input: name | Name of the module (e.g. price calculator, slug) -->
<!-- input: does | What it does and its rules (one or two sentences) -->

# Recipe: the {{name}} module

{{does}}

## Make

- The module `{{name_snake}}` (or the language's naming: `{{name_pascal}}`, `{{name_kebab}}`) where STACK.md's layout puts this kind of code, with the smallest public API that does the job.
- Its errors as the language's idiom (error values, Result types, exceptions the project already defines).

## Rules

- Pure where it can be: inputs in, outputs out; IO stays at the edges.
- Named after the domain's words, documented where the behaviour is not obvious.

## Tests

- Unit tests where STACK.md says tests live: the main cases, the edges (empty, zero, limits) and each error.
