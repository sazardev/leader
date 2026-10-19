<!-- name: SMTP -->
<!-- desc: plain SMTP with credentials from the environment and a local mail catcher (Mailpit) in development -->
<!-- for: server backend fullstack web selfhosted !game -->

## Stack

| Email | SMTP (any provider via `SMTP_URL`; Mailpit as the local mail catcher in development) | No vendor lock-in; development mail never leaves the machine |

## Project layout

```
email/sender                   the one module that opens the SMTP connection and sends (TLS, timeouts)
email/templates/               message templates, HTML + plain text
compose.yaml                   `mailpit` service: SMTP on 1025, web inbox on 8025
```

## Conventions

- `SMTP_URL` (or host, port, user, password) from the environment; production requires TLS (STARTTLS or implicit) and a timeout.
- Development and tests send to Mailpit; there is no code path that can reach a real SMTP server from a developer machine.
- Send from a job with retries; set `Message-ID` and `Reply-To` deliberately.
- Domain has SPF, DKIM and DMARC records before sending production mail.
- Addresses and header values are validated; line breaks are rejected.

## Commands

| Mail catcher | `docker compose up -d mailpit` |

## Testing

- Integration tests send through Mailpit and read the message from its API (`http://localhost:8025/api/v1/messages`).

## Rules for agents

- Never put SMTP credentials in the repository or in logs.
- Never send real mail from development or tests.
- Never build headers (To, Subject) from unvalidated input.
