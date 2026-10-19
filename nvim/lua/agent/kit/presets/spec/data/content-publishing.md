<!-- name: Content publishing -->
<!-- desc: writing and publishing: drafts, review, scheduled publishing, addresses, revisions, categories -->
<!-- for: all -->
<!-- needs: accounts roles -->
<!-- tech: database jobs search -->
<!-- design: forms data-tables search-and-filters -->

## Requirements

### Drafts and review

The system must let content be written privately and checked before readers see it.

- Given an author, when they write a piece, then it is saved as a draft that only people with access can see
- Given a draft, when the author submits it for review, then the reviewers are told and can approve it or return it with comments
- Given a returned draft, when the author fixes it and submits again, then it goes back to review

### Publishing

The system must put content in front of readers at the right moment, at a stable address.

- Given an approved piece, when it is published, then readers can open it at its address
- Given a piece with a future date, when that moment arrives, then it is published without anyone doing it
- Given a published piece, when its title changes, then its address keeps working

### Revisions and categories

The system must keep what was published before and organise content for readers.

- Given a piece, when it is saved, then the previous version can be seen and restored
- Given a piece, when it is placed in categories, then readers can browse them

## Edge cases

- [Publishing] Two pieces end up with the same address: the second is refused or changed with a notice, never replaced silently
- [Publishing] A scheduled piece is edited or unpublished before its time: the schedule follows the latest state
- [Drafts and review] Two people edit the same draft: the second one is warned before overwriting
- [Revisions and categories] A category is removed while it has content: the content is moved or kept uncategorised, never lost
- [Publishing] A published piece is deleted: its old address answers that it is gone, not a broken page

## Open questions

- [Drafts and review] Is review always needed, by whom, and can an author publish their own work?
- [Publishing] Does a piece have a date and time zone fixed by the author or by the site?
- [Revisions and categories] How many revisions are kept and for how long?
- [Publishing] Does published content need search-engine data (title, description, image), and who writes it?
