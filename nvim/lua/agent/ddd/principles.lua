-- ── Reglas de DDD que se le dan al modelo (compactas) ────────────────────────
local M = {}

M.RULES = [[
DDD (this project's layers, names and conventions are in <ddd>):
- domain: pure model; entities have identity and enforce invariants; value objects are immutable and validated at creation; repositories are interfaces (ports), one per aggregate root; no framework, DB or HTTP types.
- application: use cases orchestrate the domain; no business rules.
- infrastructure: implements ports and maps persistence models.
- interface: transport calls use cases and maps DTOs; no business logic.
Dependencies point inward; inject them through constructors typed as interfaces; one responsibility per type (SOLID); names follow the project's language and file conventions.]]

return M
