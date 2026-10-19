<!-- name: Newsletter and email campaigns -->
<!-- desc: sending email to audiences: subscribe and unsubscribe, templates, scheduling, bounces and statistics -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: email jobs -->
<!-- design: forms data-tables -->

## Requirements

### Subscribing

The system must let people join and leave an audience, and prove they agreed.

- Given a sign-up form, when a person enters their email, then they receive a confirmation and are subscribed only after confirming
- Given any campaign email, when a person opens it, then it has a working link to unsubscribe in one step
- Given a person who unsubscribed, when a campaign is sent, then they do not receive it

### Campaigns

The system must let the team write and send a message to an audience.

- Given an audience and a message, when the team sends a test, then it arrives to the chosen addresses and nobody else
- Given a campaign, when the team schedules it, then it is sent at that time in the time zone shown
- Given a campaign that was sent, when someone opens it, then the system shows to whom and when it was sent

### Delivery and statistics

The system must keep the list healthy and report results.

- Given an address that bounces, when the bounce is known, then the address is marked and no longer used
- Given a sent campaign, when the team looks at it, then they see how many were delivered, opened, clicked and unsubscribed

## Edge cases

- [Subscribing] The same address subscribes twice: one subscription, no second email
- [Campaigns] A campaign is scheduled and then edited or cancelled: only the latest version is sent, or nothing
- [Campaigns] Sending is interrupted halfway: it continues without sending twice to the same person
- [Delivery and statistics] A person marks the message as spam: they are unsubscribed and the team can see it

## Open questions

- [Subscribing] Can audiences be segmented (by tags, behavior), and may a person belong to several?
- [Campaigns] Who can write, approve and send a campaign?
- [Delivery and statistics] Are opens and clicks tracked, and what do the privacy rules of your countries require?
