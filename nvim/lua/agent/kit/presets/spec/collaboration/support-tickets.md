<!-- name: Support tickets -->
<!-- desc: a helpdesk: tickets, assignment, status, replies by email, priorities, response times, internal notes -->
<!-- for: all -->
<!-- needs: accounts notifications -->
<!-- tech: database email search -->
<!-- design: data-tables forms search-and-filters comments-threads -->

## Requirements

### Opening a ticket

The system must let a customer ask for help and follow what happens to the request.

- Given a customer, when they send a request through the form or by email, then a ticket is created and they receive a confirmation with its number
- Given a ticket, when the customer opens it later, then they see its status and every reply

### Handling tickets

The system must let the support team organise and answer the requests.

- Given a new ticket, when an agent takes it or it is assigned to them, then the owner is shown and the others see it is handled
- Given a ticket, when an agent replies, then the customer receives the reply by email and it is added to the ticket
- Given a ticket, when an agent writes an internal note, then only the team can see it
- Given a ticket, when its status or priority changes, then the change is recorded with who made it

### Response times

The system must make late tickets visible before the customer notices.

- Given a ticket with a response target, when the target is near or passed, then the ticket is marked and the team is told
- Given a customer reply on a closed ticket, when it arrives, then the ticket is reopened

## Edge cases

- [Handling tickets] Two agents answer the same ticket at the same moment: the second one is warned before sending
- [Opening a ticket] A customer sends the same request twice or replies to an automatic message: no duplicate ticket is created and the message joins the right ticket
- [Handling tickets] An internal note is included in a reply by mistake: the notes and replies are clearly distinct in the editor
- [Response times] A ticket arrives outside working hours: the clock follows the rule below
- [Handling tickets] The assigned agent leaves or is away: their open tickets are reassigned or flagged

## Open questions

- [Response times] What are the response and resolution targets, per priority, and do they run only in working hours?
- [Handling tickets] Which statuses and priorities exist, and who may close a ticket?
- [Opening a ticket] Can a customer who has no account open tickets, and how is their email checked?
- [Handling tickets] Is a ticket automatically closed after some time without reply?
