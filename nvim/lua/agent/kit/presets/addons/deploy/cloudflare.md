<!-- name: Cloudflare Workers / Pages -->
<!-- desc: deploy to Cloudflare's edge with Wrangler: Pages for static sites, Workers for server code -->
<!-- for: web js -->
<!-- default: web -->

## Stack

| Deploy | Cloudflare (Pages for static output, Workers for server routes), configured in `wrangler.toml` | Global edge, free tier, KV/D1/R2 when data is needed |

## Conventions

- Bindings (KV, D1, R2, secrets) are declared in `wrangler.toml` and typed (`wrangler types`); code never reads `process.env` directly.
- Server code uses Web-standard APIs (`fetch`, `Request`, `Response`); Node-only modules are avoided or enabled with `nodejs_compat` explicitly.
- Secrets with `wrangler secret put`, never in `wrangler.toml`.

## Commands

| Dev (edge runtime) | `wrangler dev` |
| Deploy | `wrangler deploy` |

## Rules for agents

- Never commit secrets; never add a Node-only dependency to Worker code without checking runtime compatibility.
- Keep Worker bundles small: no heavy dependencies on the request path.
