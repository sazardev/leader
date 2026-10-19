<!-- name: Notifications -->
<!-- desc: in-app, email and push notifications, preferences, unsubscribe, delivery retries -->
<!-- for: all -->
<!-- needs: accounts -->

## Requirements

### In-app notifications

The system must tell people about events that concern them inside the app.

- Given an event that concerns a person, when it happens, then a notification appears in their list with what happened and a link to it
- Given unread notifications, when the person looks at the app, then they see how many there are
- Given a notification, when they open it, then it is marked read and they reach what it is about

### Email and push

The system must send the events a person chose by email or push.

- Given an event a person chose to receive by email, when it happens, then they get an email with a link to it
- Given a device with push allowed, when such an event happens, then the device shows a push notification that opens it
- Given a sending failure, when it happens, then it is retried a few times and the in-app notification is kept either way

### Preferences

The system must let each person choose what they are notified about and how.

- Given the preferences screen, when it opens, then it lists each kind of event with its channels (in-app, email, push)
- Given a change of preferences, when it is saved, then it applies to the next notifications
- Given an email notification, when the person uses its unsubscribe link, then that kind of email stops without signing in

## Edge cases

- [Email and push] Many events of the same kind at once: they are grouped into one notification instead of a flood
- [In-app notifications] The thing a notification links to was deleted: opening it says so
- [Email and push] A person who caused an event is never notified about their own action

## Open questions

- [In-app notifications] Which events notify whom?
- [Email and push] Which channels exist at first: in-app only, email, push?
- [Preferences] Is there a quiet time or a daily digest instead of every email?
