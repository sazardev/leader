<!-- name: Pricing and checkout -->
<!-- desc: plan cards, billing toggle, checkout form, order summary, payment errors and receipts -->
<!-- for: all -->

## Components

- GUI: plan cards side by side (3 maximum, stack on narrow screens), equal height; each shows name, price, billing period, one-line audience, 5-7 feature lines with checks, and one button; highlight the recommended plan with a label and the primary-filled button, others outlined.
- GUI: a monthly/yearly toggle at the top states the saving in text ("Yearly - 2 months free") and updates every price at once; show the per-month price and the billed total in smaller text ("$8/mo, billed $96 yearly").
- GUI: show the full price early: tax, per-seat and usage charges are stated on the card or a visible line, never first revealed at the last step; the currency symbol and format follow the locale.
- GUI: checkout is one page on wide screens: form on the left, sticky order summary on the right (plan, quantity, discount, tax, total in larger weight); on narrow screens the summary collapses to a top bar with the total.
- GUI: ask only for what payment needs: email, card (number, expiry, CVC in one grouped field), billing country and postal code; use a payments provider's hosted fields; card brand icon appears while typing; format numbers as typed.
- GUI: promo code is a collapsed link "Have a code?" that expands; an applied code shows as a removable line item; an invalid one says why ("This code expired on 3 Mar").
- GUI: pay button states the amount ("Pay $96.00"), shows a spinner and is disabled while processing so double charges are impossible; keep the idempotency key per attempt.
- GUI: payment errors are specific and keep entered data: "Your card was declined. Try another card or contact your bank."; 3-D Secure opens inline; offer an alternate method.
- GUI: success screen confirms plan, amount, next billing date and the receipt link; a receipt or invoice email is sent and listed under billing with download as PDF; cancellation is as easy to find as upgrading.
- TUI: print a summary table (item, qty, price, total) and ask `Confirm payment of $96.00? [y/N]`; the payment itself opens a browser link; show the receipt URL.

## Accessibility

- Every card field has a label and autocomplete token (`cc-number`, `cc-exp`, `cc-csc`); errors are announced; the billing toggle is a labelled switch or radio group; totals are in text, not images.

## Rules for agents

- Never charge without a visible total and an explicit user action.
- Never hide cancellation or downgrade paths behind support-only flows.
