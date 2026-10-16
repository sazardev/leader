<!-- name: Domain-Driven Design -->
<!-- desc: ubiquitous language, bounded contexts, aggregates guarding invariants, value objects, domain events -->

### Domain-Driven Design

- **Ubiquitous language**: code uses the domain experts' terms (types, methods, events, tables); a renamed concept is renamed everywhere.
- **Bounded contexts** have explicit boundaries and their own model; the same word may mean different things in two contexts, and that is fine.
- **Aggregates guard invariants**: state changes only through the aggregate root's methods, which reject invalid transitions; no public setters.
- **Small aggregates**, referenced by id from other aggregates; one transaction modifies one aggregate.
- **Value objects** for concepts defined by their value (Money, Email, DateRange): immutable, validated on creation, compared by value.
- **Domain events** (past tense: `OrderPlaced`) record what happened; other aggregates and contexts react to them instead of being called directly.
- **One repository per aggregate root**, with collection-like methods in domain terms; no repositories for inner entities.
- **Anti-corruption layer** translates external systems' models at the boundary; their types never enter the domain.
- Review check: no business rule lives outside an entity, value object or domain service; invalid states cannot be constructed.
