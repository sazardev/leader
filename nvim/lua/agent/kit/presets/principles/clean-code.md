<!-- name: Clean Code -->
<!-- desc: intention-revealing names, small functions, one level of abstraction, no surprises, comments say why -->
<!-- core: true -->

### Clean Code

- **Names** reveal intent: a reader knows what a variable holds or a function does without reading its body; no abbreviations, no `data`, `info`, `tmp`, `manager`, `helper`.
- **Small functions**: one thing, one level of abstraction; ~30 lines is a smell, ~60 is a split. At most 3-4 parameters; more becomes an options/params type.
- **Guard clauses**: handle invalid cases first and return early; nesting deeper than 3 levels is refactored.
- **No surprises**: a function named like a query does not mutate; side effects are visible in the name (`save`, `send`, `delete`).
- **No magic values**: numbers and strings with meaning become named constants or configuration.
- **Comments explain why**, never what: the code says what. No commented-out code, no journal comments, no stale TODOs.
- **DRY with judgment**: remove duplicated knowledge, not similar-looking code; wait for the third occurrence before abstracting.
- **Boolean flags** that switch a function's behaviour become two functions.
- Review check: every new name reads as a sentence in its call site; no function in the diff exceeds the limits above without a reason in the change.
