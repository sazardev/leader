<!-- name: Forms and surveys -->
<!-- desc: building forms, field types, validation, collecting submissions, seeing and exporting results -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: database data-access email -->
<!-- design: forms data-tables dashboards-charts -->

## Requirements

### Building a form

The system must let a person design a form or survey without code.

- Given an editor, when a person adds fields (text, number, date, choice, file), then the form shows them in that order and they can reorder or remove them
- Given a field, when the person marks it required or sets a rule (length, range, format), then the form enforces it
- Given a form, when the person previews it, then they see it as a respondent would, without saving an answer

### Answering

The system must let respondents fill the form and be sure it was received.

- Given a published form, when a respondent fills it correctly and submits, then the answer is saved and they see a confirmation
- Given an invalid answer, when the respondent submits, then each problem is shown next to its field and what they typed is kept
- Given a form that is closed or full, when someone opens it, then they are told why it does not accept answers

### Results

The system must let the owner read what was answered.

- Given a form with answers, when the owner opens the results, then they see each answer and a summary per question
- Given the results, when the owner exports them, then they get a file with one row per answer

## Edge cases

- [Answering] A respondent submits twice (double click, reload): one answer is saved
- [Building a form] A form that already has answers is edited: the old answers stay readable and a removed field is not lost from them
- [Answering] A respondent leaves halfway: whether the progress is kept follows the rule below
- [Results] A text answer starts with `=` or `+` and is opened in a spreadsheet: it is exported as text, never run as a formula
- [Results] The owner deletes a form: its answers go too only after an explicit confirmation that says how many there are

## Open questions

- [Answering] Are answers anonymous, tied to an account, or both, and can one person answer more than once?
- [Answering] Can a respondent save progress and return, or edit their answer after sending?
- [Results] Who can see the results, and are the respondents' answers private from other respondents?
- [Building a form] Does a form have conditional fields or logic (show this question only if...)?
