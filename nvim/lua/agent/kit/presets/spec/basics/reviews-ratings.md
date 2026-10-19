<!-- name: Reviews and ratings -->
<!-- desc: people rating and reviewing items: one per person, averages, helpfulness, moderation and reports -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: database -->
<!-- design: forms comments-threads -->

## Requirements

### Rating and reviewing

The system must let a person rate an item and explain their opinion.

- Given an item, when a person submits a rating and optionally a review, then it appears with their name and date
- Given an item the person already reviewed, when they review it again, then their previous review is edited, not duplicated
- Given a review, when its author edits or deletes it, then the item's average updates

### Reading reviews

The system must help people use the reviews of others.

- Given an item with reviews, when it is shown, then it shows its average, the number of reviews and the distribution
- Given reviews, when a person sorts or filters them, then the list follows (newest, highest, lowest, most helpful)
- Given a review, when a person marks it helpful, then the count grows once per person

### Moderation

The system must keep reviews honest and civil.

- Given a review, when a person reports it, then it goes to a moderation queue with the reason
- Given a moderator, when they remove a review, then its author is told why and the average updates

## Edge cases

- [Rating and reviewing] A person reviews an item they never got: it follows the rule decided below
- [Reading reviews] An item has no reviews: it says so instead of showing a zero average
- [Moderation] A review is reported many times at once: it enters the queue once
- [Rating and reviewing] The reviewed item is deleted: its reviews are kept or removed as decided below

## Open questions

- [Rating and reviewing] Who can review: anyone signed in, or only verified buyers or users?
- [Moderation] Are reviews published at once or after approval?
- [Reading reviews] Can the owner of the item reply to a review, and is the rating scale stars, thumbs or numbers?
