<!-- name: Transactional email -->
<!-- desc: an email with HTML and plain-text templates, the project's provider, unsubscribe and a dev preview -->
<!-- for: server -->
<!-- input: name | Name of the email (e.g. welcome, invoice paid) -->
<!-- input: when | When it is sent and what it tells the person (one or two sentences) -->

# Recipe: the {{name}} email

{{when}}

## Make

- A template `{{name_snake}}` with an HTML part and a plain-text part, in the templates folder the project uses (React Email, MJML, Jinja, Go templates, the framework's mailer views), with subject, preheader and the variables it needs typed.
- A send function `send{{name_pascal}}` over the one mail module that wraps the provider from STACK.md's Email row (SMTP, Resend, Postmark, SES, SendGrid…); if there is none yet, create that module, with the sender address and the API key from the environment and listed in the example env file.
- The call at the place where the event happens, through the project's background jobs when it has them so a slow provider never slows the request.
- A way to see it in development: a preview route or script that renders it with sample data, and a local mail catcher or log transport when the stack offers one.
- Unsubscribe: a link and `List-Unsubscribe` header for anything that is not strictly transactional (security and receipt emails need none), and the preference it flips.

## Rules

- Inline styles, a single column, no web fonts or scripts; readable without images; the text part carries the same content and links.
- Escape every variable; links are absolute and built from one configured base URL.
- Failures are logged with the recipient's id, not the address, and retried only when the error is temporary.
- Never send to real addresses outside production: test and development use the catcher or an allow-list.
- Follow the existing emails: layout partial, naming, copy tone.

## Tests

- The template renders both parts with sample data, with every variable present and no unfilled placeholder.
- The send function calls the provider with the right sender, recipient, subject and body (a fake transport).
- The trigger sends once; a provider failure does not break the request and is retried or logged.
