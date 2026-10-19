<!-- name: Back office -->
<!-- desc: the internal side: finding any account or record, supporting people, acting with care -->
<!-- for: all -->
<!-- needs: accounts roles audit-log -->
<!-- tech: auth database -->
<!-- design: data-tables command-palette -->

## Requirements

### Finding and viewing

The system must let the team find any account or record and see what the person sees.

- Given a team member, when they search for an account, then they find it by name, email or identifier
- Given an account, when the team opens it, then they see its data and recent activity

### Acting with care

The system must let the team act for a person and leave a trace.

- Given a team member who acts on an account, when they do it, then the action is recorded with who, why and when
- Given a destructive action, when the team member confirms it, then a second confirmation or approval is required

## Edge cases

- [Acting with care] Acting as a person never reveals their password and is visible to the person afterwards
- [Finding and viewing] Personal data is shown only to the roles that need it for support

## Open questions

- [Acting with care] Which actions need approval from a second person?
- [Finding and viewing] Who can see which data of an account?
