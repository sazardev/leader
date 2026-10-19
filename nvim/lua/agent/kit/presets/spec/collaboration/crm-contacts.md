<!-- name: Contacts and pipeline -->
<!-- desc: people and companies, notes and activities, pipeline stages, owners, duplicates -->
<!-- for: all -->
<!-- needs: accounts roles -->
<!-- tech: database search -->
<!-- design: data-tables search-and-filters forms dashboards-charts -->

## Requirements

### Contacts and companies

The system must keep the people and companies the business deals with, and how they relate.

- Given a contact, when a person fills in their data, then it is saved and the contact shows up in searches
- Given a contact, when it is linked to a company, then the company lists it and the contact shows the company
- Given a contact, when someone opens it, then they see its notes, activities and deals in time order

### Pipeline

The system must show how far each opportunity is and who is responsible.

- Given an opportunity, when a person moves it to another stage, then the stage and the date are recorded
- Given an opportunity, when it is assigned to an owner, then only the owner and those whose role allows it can change it, and the owner finds it in their list
- Given a stage, when it is shown, then it lists its opportunities with their count and value

### Duplicates

The system must help keep one record per real person or company.

- Given a new contact, when it has the same email or a very similar name as an existing one, then the person is warned before saving
- Given two records of the same person, when they are merged, then one record remains with the notes, activities and deals of both

## Edge cases

- [Duplicates] A merge is done by mistake: what was merged and from which records is recorded so it can be checked or undone
- [Duplicates] Two records have different values for the same field: the person chooses which one is kept
- [Pipeline] The owner leaves the business: their opportunities are reassigned or flagged, none stays without an owner
- [Contacts and companies] A contact asks to be removed: their data and the links are deleted or anonymised as the rules below say
- [Pipeline] An opportunity is moved back to an earlier stage: it is allowed and recorded, not blocked

## Open questions

- [Pipeline] Which stages does the pipeline have, and can a person skip or go back?
- [Pipeline] Is the owner one person or a team, and can contacts be private to their owner?
- [Contacts and companies] Which data must a contact have, and does the business need consent recorded for contacting them?
- [Duplicates] What counts as a duplicate: same email, same phone, similar name?
