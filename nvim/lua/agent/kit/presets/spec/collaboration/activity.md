<!-- name: Activity feed -->
<!-- desc: a readable history of what happened and who did it, per item and per team -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: database realtime -->
<!-- design: notification-center -->

## Requirements

### Feed

The system must show what happened, in the order it happened, to the people who can see it.

- Given something that changes, when it happens, then an entry says who did what and when, in plain words
- Given a person who cannot see an item, when they open the feed, then nothing about that item shows

### Following

The system must let a person choose which activity they follow.

- Given an item, when a person follows it, then its activity appears in their feed
- Given a person who acted on an item, when they have not chosen, then they follow it by default

## Edge cases

- [Feed] Many small changes in a row are grouped into one entry instead of flooding the feed
- [Feed] An entry points to something that was deleted: it says so and does not fail

## Open questions

- [Feed] How long is activity kept and how far back can a person scroll?
- [Following] Does the feed also send emails or pushes, or only show inside the product?
