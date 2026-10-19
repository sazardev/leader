<!-- name: Maps and location -->
<!-- desc: places on a map: search by place or nearby, saved places, permission to use location, privacy -->
<!-- for: all -->
<!-- tech: database search -->
<!-- design: search-and-filters dialogs settings-screens -->

## Requirements

### Map

The system must show places on a map and let people explore it.

- Given a set of places, when a person opens the map, then every place appears at its position and opens its details when chosen
- Given a map with many places, when it is zoomed out, then nearby places are grouped and separate again when zooming in

### Searching places

The system must let people find places by name, address or nearness.

- Given a name or address, when a person searches, then matching places are listed and the map shows the chosen one
- Given a person who allows their location, when they search nearby, then results are ordered by distance and show it
- Given a person who does not allow their location, when they search nearby, then they can type a place instead and nothing breaks

### Saved places

The system must let people keep places they care about.

- Given a place, when a person saves it, then it shows in their list and on their map
- Given a saved place, when the person removes it, then it disappears from both

## Edge cases

- [Searching places] The device cannot find its position or it is inaccurate: the person is told and can pick the place by hand
- [Searching places] A search has no results or an address is ambiguous: the screen says so and offers the likely options
- [Map] The connection is slow or the map cannot load: the list of places still works
- [Saved places] A saved place closes or is deleted by its owner: the person sees it is no longer available instead of an empty entry
- [Searching places] The person is outside the covered area: they are told, not shown wrong results

## Open questions

- [Searching places] Is the person's location kept, and for how long, or used only while searching?
- [Map] Are places added by the business only, or can users add and edit them?
- [Searching places] Which areas and languages must addresses work for, and is a radius limit needed?
- [Saved places] Are saved places private to the person or can they be shared?
