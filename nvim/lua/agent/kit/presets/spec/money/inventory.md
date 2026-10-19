<!-- name: Inventory and stock -->
<!-- desc: stock levels, reservations, adjustments, low-stock alerts and the history that explains every change -->
<!-- for: all -->
<!-- needs: catalog -->
<!-- tech: database jobs -->
<!-- design: data-tables forms -->

## Requirements

### Stock levels

The system must know how many units of each item or variant are available.

- Given an item with stock, when a unit is sold or returned, then the available quantity changes accordingly
- Given an item with no stock left, when a person tries to buy it, then it is refused and they are told it is out of stock
- Given several locations, when stock is shown, then it says where each unit is

### Adjustments and history

The system must let authorized people correct stock and keep the reason of every change.

- Given a physical count that differs, when an authorized person adjusts the quantity, then the new level applies and the reason is required
- Given an item, when its stock changed, then the history shows who, when, how many and why

### Low-stock alerts

The system must warn before an item runs out.

- Given an item with a minimum level, when its stock falls to it, then the responsible people are notified once
- Given a restocked item, when it is back over its minimum, then the alert is cleared

## Edge cases

- [Stock levels] Two people buy the last unit at the same moment: one gets it and the other is told it is gone, never both
- [Stock levels] An order is cancelled or returns damaged: the unit goes back only if it can be sold again
- [Adjustments and history] A negative level is entered: it is refused unless backorders are allowed
- [Low-stock alerts] Stock oscillates around the minimum: the alert is not sent again and again

## Open questions

- [Stock levels] Is stock held while an item is in a cart or in an unpaid order, and for how long?
- [Stock levels] Can an item be sold without stock (backorder or pre-order)?
- [Low-stock alerts] Who receives the alerts, and is the minimum per item or global?
