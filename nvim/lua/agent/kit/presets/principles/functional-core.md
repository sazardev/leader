<!-- name: Functional core, imperative shell -->
<!-- desc: pure business logic, immutable data by default, side effects pushed to a thin shell at the edges -->

### Functional core, imperative shell

- **Pure core**: business decisions are functions of their inputs only: no IO, no clock, no randomness, no globals; same input, same output.
- **Imperative shell**: a thin outer layer reads (DB, HTTP, time), calls the core, then performs the effects the core decided.
- **Immutability by default**: data is not mutated in place; functions return new values. Mutation is local and explicit when needed for performance.
- **Decisions as data**: the core returns what should happen (commands, events, results) instead of doing it.
- **Explicit data flow**: values pass through parameters and return values, not shared mutable state or hidden context.
- **Total functions**: handle every input case; use result/option types or explicit errors instead of throwing for expected cases.
- **Small composable functions** over large stateful classes.
- **Test the core exhaustively** with plain unit tests (no fakes needed); test the shell with a few integration tests.
- Review check: new business logic has no IO calls in it; time and randomness arrive as parameters.
