<!-- name: Hexagonal architecture -->
<!-- desc: ports owned by the core, adapters at the edge, one composition root, dependencies point inward -->
<!-- core: true -->

### Hexagonal architecture

- **The core** (domain + application) contains business rules and knows nothing about HTTP, databases, queues, frameworks, ORMs or the UI.
- **Ports are owned by the core**: interfaces declared where they are used (`OrderRepository`, `PaymentGateway`, `Clock`), named in business terms, never after a technology.
- **Adapters live at the edge**: driving adapters (HTTP handlers, CLI, consumers) call use cases; driven adapters (Postgres, Stripe, SMTP) implement ports.
- **Dependency rule**: adapters → application → domain. The core never imports an adapter, a driver or a framework package.
- **No framework types in the core**: no request/response objects, ORM entities, annotations or SDK types cross into it; adapters map to and from core types.
- **One composition root** (`main`/bootstrap) wires concrete adapters into the core; nothing else instantiates infrastructure.
- **Tests through ports**: use cases are tested with in-memory fakes of their ports; adapters get their own integration tests against the real technology.
- Review check: grep the core for driver, framework and SDK imports: there are none; every new adapter implements a port declared in the core.
