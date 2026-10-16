<!-- name: API design -->
<!-- desc: contract-first, resource naming, versioning, idempotency, pagination, RFC 9457 errors, compatibility -->

### API design

- **Contract first**: the API is described (OpenAPI, protobuf, GraphQL schema) and reviewed before implementation; code and docs are generated or checked against it.
- **Resources and verbs**: plural nouns (`/orders/{id}/items`), HTTP methods with their semantics, correct status codes (201 + `Location`, 204, 404, 409, 422).
- **Consistent errors** as RFC 9457 problem details (`type`, `title`, `status`, `detail`, field errors); never leak stack traces.
- **Idempotency**: PUT/DELETE are idempotent; POST that creates or charges accepts an `Idempotency-Key` and returns the same result on retry.
- **Pagination** on every list (cursor-based for large or changing sets), with a max page size; filtering and sorting via documented query params.
- **Backward compatibility**: add optional fields, never remove or rename fields or change their meaning within a version; breaking changes get a new version and a deprecation period.
- **Versioning** is explicit (`/v1` or a header), one strategy per API.
- **Consistent naming and formats**: one case style for fields, ISO 8601 UTC timestamps, string ids, money as integer minor units plus currency.
- Review check: the contract changed in the same change as the code, and no existing client breaks.
