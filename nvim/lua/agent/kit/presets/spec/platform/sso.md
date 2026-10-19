<!-- name: Single sign-on -->
<!-- desc: signing in with a company identity provider: set-up, first sign-in, domain rules, removal of leavers -->
<!-- for: all -->
<!-- needs: accounts roles -->
<!-- tech: auth database -->
<!-- design: auth-screens settings-screens -->

## Requirements

### Connecting a provider

The system must let an organisation's administrator connect their company's identity provider.

- Given an administrator, when they enter the provider's details and run the test, then they see whether signing in works before turning it on
- Given a connection that works, when the administrator enables it, then the organisation's members can sign in through it
- Given a connection, when the administrator disables it, then members fall back to the other ways to sign in

### Signing in

The system must let a member of the organisation sign in with their company identity.

- Given a person with a company email, when they choose single sign-on, then they are sent to their provider and come back signed in
- Given a person who signs in for the first time, when the provider confirms them, then their account is created with the default role
- Given an organisation that requires it, when a member tries another way to sign in, then it is refused and they are told to use single sign-on

### Leavers and changes

The system must follow the organisation's directory when someone leaves or changes.

- Given a person removed from the provider, when the change reaches the system, then their account is deactivated and their sessions end
- Given a person whose group changes at the provider, when they next sign in, then their role follows the mapping the administrator set

## Edge cases

- [Signing in] The provider is down: members are told so and an emergency way in for administrators still works
- [Signing in] A person already has an account with the same email: it is linked after confirming it is theirs, never duplicated or taken over silently
- [Connecting a provider] The administrator turns on the requirement without having signed in through it: it is refused so they cannot lock everyone out
- [Leavers and changes] The person removed was the last administrator: the removal is held until another administrator exists
- [Signing in] A person's company email changes: the account is still found by the provider's identifier, not by the email alone

## Open questions

- [Connecting a provider] Which protocols must be supported (OIDC, SAML) and which providers must be tested?
- [Signing in] Is a person's account created on first sign-in, or only for people invited beforehand?
- [Leavers and changes] Is removal automatic from the directory or is it done by hand, and how fast must it take effect?
- [Connecting a provider] Is single sign-on available to every plan or only to some?
