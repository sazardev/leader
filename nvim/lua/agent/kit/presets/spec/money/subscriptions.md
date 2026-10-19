<!-- name: Subscriptions -->
<!-- desc: plans, trials, renewals, failed renewals, upgrades and downgrades, cancelling -->
<!-- for: all -->
<!-- needs: accounts payments -->

## Requirements

### Plans

The system must offer plans and give each account what its plan includes.

- Given the plans screen, when it opens, then each plan shows its price, billing period and what it includes
- Given an account on a plan, when it uses a feature, then it is allowed only if the plan includes it, otherwise it sees which plan does
- Given a new account, when it starts, then it is on the free plan or a trial, as decided below

### Renewals

The system must renew subscriptions and handle renewals that fail.

- Given an active subscription, when its period ends, then it is charged and renewed and a receipt is sent
- Given a failed renewal, when it happens, then the person is told, the charge is retried during a grace period and the account keeps working meanwhile
- Given a grace period that ends unpaid, when it ends, then the account moves to the free plan or is paused, as decided below

### Changing and cancelling

The system must let a person change plan or cancel by themselves.

- Given an upgrade, when they choose it, then it applies at once and they pay the prorated difference
- Given a downgrade, when they choose it, then it applies at the end of the period they already paid
- Given a cancellation, when they confirm it, then nothing more is charged and they keep the plan until the end of the paid period

## Edge cases

- [Changing and cancelling] A downgrade to a plan whose limits the account already exceeds: they are told what to remove before it applies
- [Renewals] A card that expires before the renewal: they are told in advance
- [Plans] A trial that ends: the person is told before, and is not charged without having chosen a plan

## Open questions

- [Plans] Which plans, prices and limits? Monthly, yearly or both?
- [Plans] Is there a free plan, a trial, or both? How long is the trial, and does it need a card?
- [Renewals] How long is the grace period, and what happens after it?
