<!-- name: Tags and categories -->
<!-- desc: organizing items: tags, categories, colors, renaming and merging -->
<!-- for: all -->
<!-- tech: database search -->
<!-- design: search-and-filters forms -->

## Requirements

### Tagging

The system must let people label items with tags and find them by tag.

- Given an item, when a person adds a tag, then it appears on the item and can be used to filter
- Given a tag that does not exist, when a person types it, then it is created if they are allowed to

### Managing tags

The system must let tags be renamed, merged and removed without losing items.

- Given a tag, when it is renamed, then every item shows the new name
- Given two tags, when they are merged, then the items have one tag and none appears twice

## Edge cases

- [Tagging] Tags that differ only in case or spaces are the same tag
- [Managing tags] Removing a tag that thousands of items use asks first and says how many are affected

## Open questions

- [Tagging] Can everyone create tags or only some roles, and is there a limit per item?
- [Managing tags] Are categories a fixed tree or free tags?
