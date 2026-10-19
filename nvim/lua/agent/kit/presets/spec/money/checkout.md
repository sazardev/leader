<!-- name: Cart and checkout -->
<!-- desc: buying: cart, address, payment, order confirmation and order history -->
<!-- for: all -->
<!-- needs: accounts payments -->
<!-- tech: payments email -->
<!-- design: pricing-checkout forms -->

## Requirements

### Cart

The system must let a person gather what they want and see what it costs.

- Given a product, when a person adds it, then the cart shows it with its price and the total updates
- Given a product that is no longer available, when it is in the cart, then the person is told before paying

### Checkout

The system must take the person from cart to a paid order in as few steps as it can.

- Given a cart, when the person provides delivery data and pays, then an order is created and they see its confirmation
- Given a payment that fails, when it fails, then the cart is kept and they can try another way

### Orders

The system must keep every order and let the person follow it.

- Given a paid order, when it is created, then the person receives its confirmation and can find it in their history
- Given an order, when its state changes, then the person can see the new state

## Edge cases

- [Checkout] The price or stock changes while the person is paying: they are told what changed before being charged
- [Checkout] The person double-clicks pay or reloads on the confirmation: one order, one charge
- [Cart] A person who is not signed in fills a cart and signs in: the cart is kept

## Open questions

- [Checkout] Guest checkout, or an account is required?
- [Orders] Which states does an order go through, and who can cancel and until when?
- [Cart] Is stock reserved while it is in a cart, and for how long?
