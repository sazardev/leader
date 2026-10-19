<!-- name: TypeScript API route -->
<!-- desc: a route with schema validation, the service it calls, and tests -->
<!-- for: ts+server js+server -->
<!-- input: name | What the route does (e.g. create order, list invoices) -->
<!-- input: route | Method and path (e.g. POST /orders) -->

# Recipe: {{name}} ({{route}})

## Make

- The route `{{route}}` on the server framework STACK.md names (Hono, Elysia, Fastify, Express, NestJS controller), registered where the others are.
- Request validation with the project's schema library (Zod, Valibot, TypeBox, class-validator) and a typed response.
- A service function `{{name_camel}}` that holds the rule, independent of the framework; data through the project's data layer (Drizzle, Prisma, Kysely, a repository).

## Rules

- One error mapping: invalid input 400 with the field, not found 404, conflict 409, everything else 500 without internals.
- No `any`; types inferred from the schema where the project does it.
- Follow the existing routes: file shape, middleware, how they respond.

## Tests

- With the project's test runner (Vitest, Bun test, Jest): the route through the framework's test client (happy path, invalid input, each service error) and the service alone.
