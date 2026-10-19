<!-- name: Coupons and promotions -->
<!-- desc: discounts: codes, rules, limits, validity and how they show in the price -->
<!-- for: all -->
<!-- needs: payments -->
<!-- tech: payments -->
<!-- design: pricing-checkout forms -->

## Requirements

### Using a code

The system must apply a discount when a person enters a valid code.

- Given a valid code, when it is entered, then the discount shows in the price before paying
- Given an invalid, expired or used-up code, when it is entered, then the person is told which one it is

### Creating promotions

The system must let the people in charge create promotions with clear rules.

- Given a promotion, when it is created, then it has its discount, its validity and its limits (per person, in total)
- Given a promotion, when it is switched off, then it stops applying at once but past orders keep it

## Edge cases

- [Using a code] Two promotions apply to the same order: the rule for combining them is applied the same way every time
- [Using a code] The same code used at the same moment by many people never goes over its limit
- [Creating promotions] A discount bigger than the price never leaves a negative total

## Open questions

- [Creating promotions] Can discounts be combined, and which wins when they cannot?
- [Using a code] Are there rules by product, by customer or by minimum amount?
