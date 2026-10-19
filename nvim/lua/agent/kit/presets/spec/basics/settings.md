<!-- name: Profile and preferences -->
<!-- desc: the person's profile, avatar, language, theme and notification choices -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: database -->
<!-- design: settings-screens forms -->

## Requirements

### Profile

The system must let a person see and edit how they appear to others.

- Given a signed-in person, when they edit their name or picture and save, then the change shows everywhere they appear
- Given an invalid value, when they save, then the field says what is wrong and nothing else is lost

### Preferences

The system must remember a person's choices and apply them on every device.

- Given a person who changes a preference, when they save it, then it applies at once and on their other sessions
- Given a new person, when they have chosen nothing, then sensible defaults apply

## Edge cases

- [Profile] Two people edit the same profile at once (a person and an administrator): the last save wins and says so
- [Preferences] A saved choice is no longer offered (a removed language): the default is used without an error

## Open questions

- [Profile] Which profile fields are public, and which only the person sees?
- [Preferences] Which preferences exist (language, theme, time zone, density) and which are per device?
