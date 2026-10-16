<!-- name: SOLID -->
<!-- desc: single responsibility, open/closed, substitution, small interfaces, depend on abstractions -->
<!-- core: true -->

### SOLID

- **Single responsibility**: a module, type or function has one reason to change. If describing it needs "and", split it.
- **Open/closed**: add behaviour by adding code (a new implementation, a new strategy, a new handler), not by growing `switch`/`if` chains in existing code.
- **Liskov substitution**: every implementation of an interface honours its full contract (inputs, outputs, errors, side effects); no implementation panics or ignores a method it "does not support".
- **Interface segregation**: interfaces are small and owned by the consumer; a consumer never depends on methods it does not call.
- **Dependency inversion**: business code depends on interfaces it defines; concrete adapters (DB, HTTP, queues, clocks, random) are injected from the composition root.
- Review check: no constructor creates its own infrastructure; no type takes more than ~5 dependencies (a sign it does too much).
