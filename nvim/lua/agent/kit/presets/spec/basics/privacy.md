<!-- name: Privacy and personal data -->
<!-- desc: consent, what is kept, a person's right to see, export and delete their data -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: database email -->
<!-- design: settings-screens dialogs -->

## Requirements

### Consent

The system must ask for what needs consent before using it and remember the answer.

- Given a person who has not answered, when they use the product, then nothing that needs consent is used
- Given a person who gave consent, when they change their mind, then they can withdraw it as easily as they gave it

### Access and export

The system must let a person get a copy of the data it keeps about them.

- Given a signed-in person, when they ask for their data, then they receive it in a readable format within a stated time
- Given a request, when it is ready, then the person is told and the file is available for a limited time

### Deleting a person's data

The system must let a person delete their account and the personal data tied to it.

- Given a person who asks to delete their account, when they confirm, then they are told what will be erased and what the law requires to keep
- Given a confirmed deletion, when the period of grace ends, then their personal data is erased everywhere it is kept

## Edge cases

- [Consent] Children below the age allowed to consent: the product does not collect what needs it
- [Deleting a person's data] Data tied to other people (a shared document, an invoice) is anonymized or kept, not erased for everyone
- [Access and export] Two requests at once for the same person: they get one file, not two

## Open questions

- [Consent] Which uses need consent (analytics, marketing, third parties) and where is it recorded?
- [Deleting a person's data] How long is a deletion reversible, and what must be kept by law?
- [Access and export] Which regulations apply (GDPR, CCPA, local law)?
