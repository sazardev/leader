<!-- name: Testing -->
<!-- desc: test pyramid, behaviour over implementation, deterministic tests, fakes for owned ports, test per bug -->
<!-- core: true -->

### Testing

- **Pyramid**: many fast unit tests, fewer integration tests against real dependencies (containers), a few end-to-end tests of critical flows.
- **Test behaviour, not implementation**: assert on outputs and observable effects through public APIs; refactoring must not break tests.
- **Arrange, Act, Assert**: one behaviour per test, named after it (`rejects_order_without_items`); table-driven for variations.
- **Deterministic**: no `sleep`, no real clock, randomness or network in unit tests; inject clocks, id generators and seeds.
- **Fakes over mocks** for ports you own (in-memory repository); mocks only to assert interactions that are the behaviour (an email was sent).
- **Isolated**: tests do not depend on order or shared state; each creates its data and cleans up (transactions rolled back, temp dirs).
- **Every bug gets a regression test** that fails before the fix and passes after it.
- **Coverage is a signal, not a target**: uncovered critical paths matter; chasing a percentage with trivial tests does not.
- Review check: every changed behaviour has a test in the same change; the suite passes repeatedly and in parallel.
