<!-- name: First run and onboarding -->
<!-- desc: what a new person sees first: welcome, empty states, a guided first success -->
<!-- for: all -->
<!-- tech: analytics -->
<!-- design: onboarding empty-states -->

## Requirements

### First run

The system must lead a new person to their first useful result in a few steps.

- Given a person who arrives for the first time, when they open the product, then they see what it is for and the one next step
- Given a person in the middle of the steps, when they leave and return, then they continue where they stopped
- Given a person who does not want a guide, when they skip it, then they can start using the product and find it again later

### Empty states

The system must explain every empty place and offer the action that fills it.

- Given a list with nothing in it, when it is shown, then it says what will appear there and offers the action to add the first one
- Given a person who has no permission to add, when they see an empty place, then it says who can

## Edge cases

- [First run] A person arrives through an invitation or a shared link: they land on what was shared, not on the generic welcome
- [Empty states] An empty result caused by filters is told apart from a list that is really empty

## Open questions

- [First run] What is the first success a new person must reach, and how fast?
- [Empty states] Do empty places offer sample data, and can it be removed afterwards?
