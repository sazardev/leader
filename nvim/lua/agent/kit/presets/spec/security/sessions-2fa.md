<!-- name: Two-step sign-in and sessions -->
<!-- desc: a second factor, trusted devices, active sessions and signing out everywhere -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: auth email -->
<!-- design: auth-screens settings-screens -->

## Requirements

### Second factor

The system must let a person protect their account with a second step.

- Given a person who turns it on, when they finish the setup, then they get recovery codes and are asked for the second step on their next sign-in
- Given a wrong second-step code, when it is entered several times, then further tries are delayed

### Sessions and devices

The system must show where a person is signed in and let them end it.

- Given a person, when they open their sessions, then they see each device with its place and last use
- Given a session, when the person ends it, then that device is signed out at once

### Recovery

The system must give a way back in when the second step is lost, without opening a door for others.

- Given a person who lost their second step, when they use a recovery code, then they sign in and are asked to set it up again

## Edge cases

- [Second factor] A person with no recovery codes left and no device: recovery goes through a slower, verified process
- [Sessions and devices] A password change ends every other session
- [Recovery] Each recovery code works once and its use is notified to the person

## Open questions

- [Second factor] Is it required for everyone, for some roles, or optional?
- [Sessions and devices] How long does a session last, and is there a trusted-device option?
