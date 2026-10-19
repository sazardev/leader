<!-- name: Product catalog -->
<!-- desc: what is sold or offered: items with variants, prices, categories, images, availability and detail pages -->
<!-- for: all -->
<!-- tech: database search storage -->
<!-- design: search-and-filters data-tables -->

## Requirements

### Items and variants

The system must describe each item with the data a person needs to choose it, including its variants.

- Given an item, when it is published, then it shows its name, description, images and price
- Given an item with variants (size, color), when a person picks one, then the price, images and availability shown are those of that variant
- Given an item without images, when it is shown, then a neutral placeholder takes their place

### Prices

The system must show each price clearly and consistently.

- Given an item with a price, when it is shown anywhere, then it appears in the same currency and format
- Given an item with a discounted price, when it is shown, then the original and the current price are both visible
- Given a price that changes, when a person already has the item in view, then the next time it is shown it carries the new price

### Browsing the catalog

The system must let a person find items by category and open one in detail.

- Given categories, when a person opens one, then they see only the items that belong to it
- Given an item that is not available, when it is shown, then it says so and why (out of stock, discontinued)
- Given an item the person cannot see (draft, hidden), when they open its address, then they get a not found message

## Edge cases

- [Items and variants] A variant is removed while a person is looking at it: they are told it is gone and offered the others
- [Prices] An item has no price yet: it is shown as unavailable to buy, never as free
- [Browsing the catalog] An item moves to another category: its old address still reaches it
- [Items and variants] Two editors change the same item at once: the second is warned before overwriting the first

## Open questions

- [Items and variants] Which attributes do items have, and how many variants can one item have?
- [Prices] Which currencies, are prices with or without tax, and can prices differ per country or customer group?
- [Browsing the catalog] Can an item belong to several categories, and how deep can categories nest?
