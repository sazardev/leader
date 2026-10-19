<!-- name: Auth screens -->
<!-- desc: sign in/up, reset, verification, 2FA and social buttons without leaking which field was wrong -->
<!-- for: all -->

## Components

- GUI: auth screens are a single centered card, max 400 px, logo on top, one heading ("Sign in to Acme"), no navigation chrome; primary button full width, 44 px high.
- GUI: sign in: email, password with a show/hide toggle, "Forgot password?" link under the password, "Sign in" button; allow browser autofill and password managers (`autocomplete="username"`, `current-password`, `new-password`, `one-time-code`).
- GUI: social sign-in buttons (Continue with Google, Apple) are outlined, full width, above or below an "or" divider, same height as the primary button; follow each provider's brand guidelines for logo and label.
- GUI: failed login says "Email or password is incorrect" for any credential error; reset requests always answer "If an account exists, we sent a link" so account existence never leaks; rate-limit and show "Too many attempts. Try again in 5 minutes."
- GUI: sign up asks the minimum (email and password, or social); show password rules as a live checklist while typing and prefer length (12 or more characters) over composition rules; confirm password fields are not needed with a show toggle.
- GUI: verification: a 6-digit code as one input with `inputmode="numeric"`, auto-advance and paste support, "Resend code" disabled for 30 s with a visible countdown, and an "Use a different email" link.
- GUI: 2FA: prompt for the code, offer "Use a recovery code" and "Remember this device for 30 days"; show recovery codes once at setup with copy and download actions and a required "I saved them" checkbox.
- GUI: reset flow: email, then link, then a new password screen with the same rules; after success sign in automatically or go to sign in with a clear "Password updated" message; links expire and expired ones say so with a request-new-link action.
- GUI: after sign in return the user to the page they came from; sessions expire with a re-auth dialog that keeps unsaved work.
- TUI: prompts for user and password with input hidden (no echo, no asterisks needed), device-code flow prints the URL and code in a box and polls with a spinner; tokens are stored in the OS keychain, never printed.

## Accessibility

- Errors are announced and linked to fields; the code input is labelled with its length; never use CAPTCHA without an accessible alternative.

## Rules for agents

- Never reveal whether an email, username or phone is registered.
- Never put the password, token or code in a URL, a log or a toast.
