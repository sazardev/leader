<!-- name: Favorites and wishlists -->
<!-- desc: saving items for later: favorites, named collections, sharing and what happens when an item disappears -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: database -->
<!-- design: empty-states toasts-feedback -->

## Requirements

### Saving items

The system must let a person keep items they want to come back to.

- Given an item, when a person marks it as a favorite, then it is saved and the mark shows everywhere the item appears
- Given a favorite, when the person unmarks it, then it is removed from their saved items
- Given a person with favorites, when they open their saved items, then they see them, newest first

### Collections

The system must let a person organize what they saved.

- Given saved items, when a person creates a collection and adds items to it, then the items appear in it
- Given a collection, when its owner renames or deletes it, then the items stay saved

### Sharing a collection

The system must let a person show a collection to others.

- Given a collection, when its owner shares it, then the people with the link see its items but cannot change them
- Given a shared collection, when its owner stops sharing, then the link no longer works

## Edge cases

- [Saving items] A saved item is deleted or becomes unavailable: it is shown as no longer available instead of disappearing without a word
- [Saving items] The person taps the mark twice quickly: the final state matches the last tap
- [Collections] An item is added to a collection it is already in: it is not duplicated
- [Sharing a collection] A shared collection contains an item the viewer cannot see: that item is hidden for them

## Open questions

- [Saving items] Is there a limit of saved items per person?
- [Collections] Can an item be in several collections, and can collections be collaborative?
- [Sharing a collection] Can a person without an account view a shared collection?
