<!-- name: Accounts and sign-in -->
<!-- desc: sign up, sign in, sessions, password reset, email verification, lockout -->
<!-- for: all -->
<!-- tech: auth database email -->
<!-- design: auth-screens forms -->

## Requirements

### Sign up

The system must let a person create an account with an email and a password.

- Given a new email and a password that meets the rules, when they sign up, then the account exists and they are signed in
- Given an email that already has an account, when they sign up, then they see that it is taken and a link to sign in instead
- Given a password that breaks a rule, when they sign up, then they see which rule it breaks and nothing is created

### Sign in

The system must let a person with an account sign in and stay signed in until they sign out or the session expires.

- Given the right email and password, when they sign in, then they reach the screen they were going to
- Given a wrong email or password, when they sign in, then they see one message that does not say which of the two was wrong
- Given a signed-in person, when they sign out, then their session ends on that device and protected screens ask them to sign in

### Password reset

The system must let a person who forgot their password set a new one through their email.

- Given any email, when they ask for a reset, then they see the same confirmation whether the account exists or not
- Given a reset link, when they open it within its lifetime and set a valid password, then the old password stops working and they are signed in
- Given a used or expired reset link, when they open it, then they are told so and can ask for a new one

### Email verification

The system must confirm that a person owns the email of their account.

- Given a new account, when it is created, then a verification email is sent
- Given a verification link, when they open it, then the email is marked verified
- Given an unverified account, when they use something that needs a verified email, then they are told to verify and can resend the email

## Edge cases

- [Sign in] Many failed attempts on one account: it is locked for a while and the owner can unlock it through their email
- [Sign up] Emails differing only in letter case or surrounding spaces are the same account
- [Password reset] Asking for several resets: only the newest link works
- [Sign in] A session used after the password changed elsewhere: it ends and asks to sign in again

## Open questions

- [Sign in] How many failed attempts lock an account, and for how long?
- [Sign in] How long does a session last without activity, and is there a "remember me"?
- [Sign up] Which sign-in methods besides email and password (Google, Apple, magic link, none)?
- [Sign up] What are the password rules (length, breached-password check)?
- [Email verification] Can an unverified account use the app, and what can it not do?
