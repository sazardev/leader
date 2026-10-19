<!-- name: Comments and mentions -->
<!-- desc: discussion on items: comments, replies, mentions, edits and deletions -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: database realtime -->
<!-- design: comments-threads -->

## Requirements

### Commenting

The system must let people discuss an item where it lives.

- Given an item, when a person writes a comment, then it appears under it with who wrote it and when
- Given a comment, when someone replies, then the reply shows under it in order

### Mentions

The system must let a person call someone into the conversation.

- Given a comment, when it mentions a person who can see the item, then they are notified with a link to it
- Given a mention of someone who cannot see the item, when the comment is sent, then the author is told and nobody is notified yet

### Editing and removing

The system must let authors fix or remove their comments without rewriting history.

- Given a comment of mine, when I edit it, then it shows it was edited
- Given a comment with replies, when its author deletes it, then the replies stay and the place says it was removed

## Edge cases

- [Commenting] Two people comment at the same moment: both appear in order without losing either
- [Mentions] A mentioned person leaves the team: the mention stays as text and nobody is notified
- [Editing and removing] An administrator removes an offensive comment: it is recorded who did it and why

## Open questions

- [Commenting] Is there rich text, attachments or only plain text?
- [Editing and removing] For how long can an author edit a comment?
- [Mentions] Can groups be mentioned (everyone, a role)?
