<!-- name: One file, one responsibility -->
<!-- desc: small cohesive files, feature folders, explicit public surface, no utils dumping grounds -->
<!-- core: true -->

### One file, one responsibility

- **One file = one responsibility**: one entity, one use case, one handler group, one component. If its description needs "and", it is two files.
- **Size limits**: ~300 lines is a soft limit, ~500 a hard one; a file over it is split by responsibility, not by line count.
- **Folders by feature**, not by technical type: `orders/` holds its entity, use cases, adapters and tests; shared kernels stay small and explicit.
- **Explicit public surface**: each module exposes a small API (index/exports/package-level types); everything else is private and may change freely.
- **No dumping grounds**: no `utils`, `helpers`, `common`, `misc` files; a helper lives next to its only user or in a module named for what it does.
- **High cohesion, low coupling**: things that change together live together; modules talk through interfaces or events, never through each other's internals.
- **Replaceable modules**: deleting or swapping a module touches its folder and the composition root, nothing else.
- **No cycles**: module dependencies form a DAG; a cycle is broken by extracting the shared concept or inverting a dependency.
- Review check: each new file can be described in one sentence; no import reaches into another module's private files.
