<!-- name: Vercel -->
<!-- desc: git-push deploys with preview URLs per branch; framework-native builds -->
<!-- for: ts -->
<!-- default: nextjs nextjs-supabase t3 -->

## Stack

| Deploy | Vercel (git integration: production from `main`, a preview deployment per pull request) | Zero-config for the framework, previews for every change |

## Conventions

- Environment variables are set per environment (Production, Preview, Development) in Vercel and pulled locally with `vercel env pull`; `.env.local` is git-ignored.
- Every pull request is reviewed on its preview URL before merging.
- Long-running or scheduled work goes to background jobs or cron routes with explicit time limits, not to request handlers.

## Commands

| Deploy (manual) | `vercel deploy --prod` |
| Pull env | `vercel env pull .env.local` |

## Rules for agents

- Never commit `.env.local` or secrets.
- Never expose a server secret through a public (`NEXT_PUBLIC_`, `VITE_`) variable.
