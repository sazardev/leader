<!-- name: RevenueCat -->
<!-- desc: in-app purchases and subscriptions for iOS and Android with entitlements and server webhooks -->
<!-- for: mobile flutter swift jvm !server !game -->

## Stack

| Payments | RevenueCat (App Store and Google Play subscriptions behind one SDK; offerings, entitlements, webhooks) | Receipt validation and store differences handled for you |

## Project layout

```
lib/purchases/                 wrapper around the SDK: configure, offerings, purchase, restore, entitlement stream
```

## Conventions

- Configure the SDK once at startup with the public SDK key per platform; the secret API key is only used on a server.
- The app asks "does the user have the `pro` entitlement", never "which product did they buy".
- Offerings and prices come from RevenueCat, never hard-coded; show the store's localized price string.
- Identify the user with the same id as your backend (`logIn`) so purchases follow the account; provide a Restore Purchases button.
- The backend trusts RevenueCat webhooks (authorization header checked) or its REST API, never the client's word.

## Testing

- Test with sandbox accounts (App Store sandbox, Google Play license testers); cover purchase, cancel, restore and expiry.
- Hide the SDK behind an interface so UI tests use a fake entitlement source.

## Rules for agents

- Never put the secret API key in the app.
- Never unlock paid features from a local flag alone; read the entitlement.
- Never remove the Restore Purchases flow; the stores require it.
