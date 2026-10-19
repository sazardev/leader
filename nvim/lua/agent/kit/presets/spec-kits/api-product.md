<!-- name: API product -->
<!-- desc: A service developers build on: API keys, plans, usage limits, audit trail, abuse control and uptime promises -->
<!-- modules: api accounts sessions-2fa subscriptions audit-log abuse observability reliability reports settings -->
<!-- tech: database auth payments email jobs analytics e2e-testing -->
<!-- design: data-tables settings-screens dashboards-charts pricing-checkout auth-screens forms -->
<!-- stacks: go-api nestjs python-fastapi node-hono rust-axum bun-hono -->

**Who it is for.** Companies that sell access to a capability through an API rather than a screen. The customers are developers, so documentation, stable contracts and honest limits matter as much as features.

**What it adds.** The API module covers keys, versioning, errors and documentation. Accounts and sessions with two-factor protect the dashboard where keys live, subscriptions turn plans and usage into billing, and reports show customers their own usage. The audit log, abuse control, observability and reliability cover what an API owes its users: traceability, fair limits, visibility and uptime.

**Decide first.**
- What do you charge for: requests, data, seats or outcomes? Is there a free tier?
- Which rate limits and quotas apply per key and per plan, and what happens when exceeded?
- How do you version the API, and how long do you support old versions?
- What uptime and latency do you promise, and what do you owe when you miss it?
- Do customers manage teams and several keys, or is it one key per person?
