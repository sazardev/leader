<!-- name: Seats and team billing -->
<!-- desc: pricing per seat or team: adding and removing members, proration, usage limits and overage -->
<!-- for: all -->
<!-- needs: subscriptions workspaces -->
<!-- tech: payments database -->
<!-- design: pricing-checkout settings-screens -->

## Requirements

### Seats

The system must tie the number of paid seats to the people who can use the workspace.

- Given a workspace with a plan, when a member is added, then they take a seat and the person who pays sees the new cost before confirming
- Given a workspace with no free seats, when someone is invited, then the person who pays is asked to add seats first
- Given a member who is removed, when their seat is freed, then it can be given to someone else

### Proration

The system must charge the right amount when seats change in the middle of a period.

- Given a seat added mid-period, when it is confirmed, then the charge is the part of the period that remains
- Given a seat removed mid-period, when it is confirmed, then the effect on the bill is shown and applied as decided below

### Usage limits and overage

The system must make limits visible before they are reached.

- Given a plan with a limit, when usage approaches it, then the workspace administrators are warned
- Given a limit that is reached, when someone goes over it, then the system applies the rule below (block, upgrade offer or overage charge) and says which

## Edge cases

- [Seats] Several administrators add seats at the same time: the count and the charge stay correct
- [Seats] A member is removed who owns work: their work stays with the workspace
- [Proration] A payment for the extra seats fails: the seats are not granted and the administrators are told
- [Usage limits and overage] The limit is reached in the middle of a bulk action: what fit is done and the rest is reported

## Open questions

- [Seats] Do pending invitations take a seat, and can guests or read-only members be free?
- [Proration] Is a removed seat credited at once, at the end of the period or never?
- [Usage limits and overage] Which usage is measured, what are the limits per plan and what happens when they are exceeded?
