<!-- name: Documentation as code -->
<!-- desc: docs live in the repo and change with the code: README, AGENTS.md, ADRs, public API docs -->

### Documentation as code

- **Docs change with the code**: a change that alters behaviour, commands, configuration or structure updates README, AGENTS.md, STACK.md or SPEC.md in the same commit.
- **README** answers: what it is, how to run it locally in minutes, how to test it, where to go next.
- **Architecture Decision Records** (`docs/adr/NNNN-title.md`: context, decision, consequences) for every significant or hard-to-reverse decision; ADRs are superseded, never edited away.
- **Public APIs are documented** where they are declared (docstrings/doc comments): what it does, parameters, errors, an example when not obvious.
- **No duplicated truth**: generate docs from code and schemas where possible (OpenAPI, CLI help); link instead of copying.
- **Write for the reader**: short sentences, real commands that work when pasted, examples over prose.
- **Delete stale docs**: wrong documentation is worse than none.
- Review check: every user-visible or developer-visible change in the diff is reflected in the docs it touches.
