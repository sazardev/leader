<!-- name: Clean Architecture -->
<!-- desc: entities, use cases, interface adapters, frameworks; the dependency rule and DTOs at every boundary -->

### Clean Architecture

- **Four rings**: entities (enterprise rules) → use cases (application rules) → interface adapters (controllers, presenters, gateways) → frameworks and drivers.
- **Dependency rule**: source code dependencies point inward only; an inner ring never names anything declared in an outer one.
- **One use case per file/class**, named as an action (`PlaceOrder`, `CancelSubscription`), with its own input and output models.
- **DTOs at boundaries**: data crossing a ring is a plain structure defined by the inner ring; entities never leak to controllers, views or the database layer.
- **Gateways are interfaces** declared by use cases and implemented in the adapters ring.
- **Presenters format output** for the delivery mechanism; use cases return data, never HTTP status codes, HTML or JSON.
- **Frameworks are details**: they are plugged in at the outer ring and could be replaced without touching use cases or entities.
- Review check: every new use case has its own file, input/output types and a unit test with fake gateways; no inner file imports an outer package.
