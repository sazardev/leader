<!-- name: AI app (Next.js + Vercel AI SDK) -->
<!-- desc: TypeScript Next.js with the AI SDK: streaming chat, tool calling, structured output with Zod, evals -->

# STACK.md: AI app (Next.js + Vercel AI SDK)

## Summary

A web app with AI features built on Next.js (App Router) and the Vercel AI SDK: streaming text and chat UIs, tools the
model can call (each a typed server function), and structured output validated with Zod. The model provider is chosen in
one place, every call records usage, and an eval script guards prompts and tools against regressions.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, strict) | Types end to end, from tool schemas to UI |
| Framework | Next.js 15 (App Router, Route Handlers, Server Actions) | Streaming responses, server-only secrets |
| AI | Vercel AI SDK (`ai`, `@ai-sdk/react`, a provider package) | `streamText`, `generateObject`, tools, `useChat` |
| Schemas | Zod | Tool inputs and structured outputs validated |
| UI | React 19 + shadcn/ui + Tailwind CSS 4 | Accessible primitives |
| Data | Drizzle ORM + PostgreSQL | Conversations, usage logs |
| Testing | Vitest (units, mocked model) + Playwright (chat flow) | |
| Evals | `evals/*.eval.ts` run with Vitest against a fixed dataset | Prompt/tool regressions |
| Package manager | pnpm | |
| Lint/format | ESLint (typescript-eslint strict) + Prettier | |

## Project layout

```
app/
  (chat)/page.tsx                  chat page (client component uses useChat)
  api/chat/route.ts                POST: streamText with tools, returns a UI message stream
lib/
  ai/
    model.ts                       THE model choice (provider + id + settings), one place
    prompts/
      assistant.v2.ts              versioned system prompts (exported strings)
    tools/
      search-orders.ts             one tool per file: description, Zod input schema, execute()
      create-ticket.ts
    schemas/
      ticket-summary.ts            Zod schemas for generateObject outputs
    usage.ts                       records tokens, latency, model, prompt version per call
  db/
    schema.ts                      Drizzle tables (conversations, messages, usage)
    client.ts
features/
  chat/
    components/message-list.tsx    rendering of text, tool calls and tool results
    components/composer.tsx
evals/
  assistant.eval.ts                dataset + assertions (tool chosen, schema valid, answer contains)
  dataset.json
```

Dependency direction: `app → features → lib`; `lib/ai/tools` call domain/data functions, never UI code.

## Conventions

- The model is chosen only in `lib/ai/model.ts`; routes import it, never a provider directly.
- One tool per file with a precise `description`, a Zod `inputSchema` and a pure-as-possible `execute`; tools validate
  permissions themselves (the user in the session), never trust model arguments.
- Structured outputs use `generateObject`/`streamObject` with a Zod schema; never parse JSON out of free text.
- System prompts are versioned constants (`assistant.v2.ts`); changing behaviour means a new version.
- Every model call goes through a wrapper that records usage (tokens, latency, model, prompt version) in the database.
- Streaming routes set `maxDuration` and a `maxSteps`/step limit for tool loops; every call has an abort signal.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` |
| Typecheck | `pnpm exec tsc --noEmit` |
| Test | `pnpm test` |
| Evals | `pnpm vitest run evals` |
| E2E | `pnpm exec playwright test` |
| Lint | `pnpm lint` |

## Testing

- Units: tools' `execute` with a test database or fakes; schemas with valid/invalid samples; prompt builders.
- Route tests with a mock language model (`MockLanguageModelV2`-style test helpers from the SDK) to assert tool wiring
  and streaming without network.
- Evals: a small dataset run against the real model on demand (not in every CI run); results stored and compared.
- E2E: one Playwright flow for sending a message and seeing a streamed answer with a tool result.

## Quality gates

- `tsc --noEmit`, lint and tests green; evals re-run and reported for prompt, tool or model changes.
- No provider SDK import outside `lib/ai/`; no API key reachable from client components (`server-only`).

## Dependencies

- Allowed: the table above.
- Do NOT use: calling provider REST APIs by hand (the SDK handles streaming and tools), LangChain-style abstractions
  over the SDK, client-side model calls with exposed keys, `JSON.parse` of model text instead of `generateObject`.

## Rules for agents

- Import the model only from `lib/ai/model.ts`; never hardcode a provider or model id elsewhere.
- Every tool lives in its own file with a Zod input schema and a clear description; register it in the route explicitly.
- Tools check authorization against the session; never act on ids the model provides without checking ownership.
- Use `generateObject`/`streamObject` with Zod for structured data; never regex or `JSON.parse` model text.
- Version system prompts; never edit a shipped prompt in place.
- Record usage for every model call through `lib/ai/usage.ts`.
- Set step limits, `maxDuration` and abort handling on streaming routes.
- Keep secrets server-side (`import "server-only"` in `lib/ai/*`).
- Add or update an eval case when a tool or prompt changes behaviour.
