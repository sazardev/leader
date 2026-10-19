<!-- name: Sharing and links -->
<!-- desc: giving access to one item: by person, by link, with a role and an end date -->
<!-- for: all -->
<!-- needs: accounts roles -->
<!-- tech: auth -->
<!-- design: dialogs -->

## Requirements

### Sharing with people

The system must let the owner of an item give others access to it.

- Given an item I own, when I share it with a person and a level of access, then they can open it with that level
- Given a shared item, when I remove someone, then they lose access at once

### Links

The system must let the owner share an item through a link that can be limited and revoked.

- Given an item, when I create a link, then I choose who can use it: anyone, or only signed-in people
- Given a link, when I revoke it, then it stops working at once and says it is no longer available

### Expiry

The system must let access end by itself.

- Given a share with an end date, when the date arrives, then the access ends and the owner is told

## Edge cases

- [Links] A link is forwarded to someone else: what they can do is exactly what the link allows, no more
- [Sharing with people] An item is shared with a person who does not have an account yet: they see it after they create one
- [Expiry] A person is working on the item when access ends: their last save is kept and the next one is refused

## Open questions

- [Links] Can a link be protected with a password, and does opening it need an account?
- [Sharing with people] Which levels of access exist (view, comment, edit) and can a person share further?
