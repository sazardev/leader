<!-- name: Calendar and booking -->
<!-- desc: availability, booking a slot, reminders, rescheduling and cancelling, time zones -->
<!-- for: all -->
<!-- needs: accounts notifications -->
<!-- tech: database email jobs -->
<!-- design: forms dialogs navigation-shell -->

## Requirements

### Availability

The system must let whoever offers a service say when they can be booked.

- Given a provider, when they set their weekly hours and days off, then only free times inside them can be booked
- Given a time that is already taken, when someone looks for a slot, then it is not offered

### Booking

The system must let a person book a free slot and know it is theirs.

- Given a free slot, when a person books it, then it is reserved for them and both sides receive a confirmation with the date, time and place
- Given two people who pick the same slot, when both confirm, then only the first one gets it and the other is offered other slots
- Given a booking, when the time is near, then both sides receive a reminder

### Changing a booking

The system must let a booking be moved or cancelled without losing track of it.

- Given a booking, when a person reschedules it to another free slot, then the old slot is freed and both sides are told
- Given a booking, when it is cancelled, then the slot is freed and the other side is told who cancelled and when

## Edge cases

- [Booking] Two people book the last slot at the same moment: exactly one booking exists, never two
- [Booking] The person and the provider are in different time zones: every time is shown in the viewer's zone and the zone is named
- [Availability] The clocks change (daylight saving) between booking and appointment: the appointment keeps its real moment and the reminder fires at the right time
- [Availability] A provider blocks a day that already has bookings: they are told which bookings are affected and what happens to them
- [Changing a booking] A person cancels at the last minute: the rule below applies and they see it before confirming

## Open questions

- [Availability] How long is a slot, is there a buffer between bookings, and how far ahead can people book?
- [Changing a booking] Until when can a booking be cancelled or moved for free, and is there a penalty after?
- [Booking] Is a booking confirmed at once or does the provider have to accept it?
- [Booking] Can a booking have several attendees, and is there a limit per slot?
