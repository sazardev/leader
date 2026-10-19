<!-- name: Invoices and receipts -->
<!-- desc: the documents after a payment: numbered invoices, receipts, tax data, downloads -->
<!-- for: all -->
<!-- needs: payments -->
<!-- tech: payments storage email -->
<!-- design: pricing-checkout -->

## Requirements

### Issuing

The system must produce an invoice or receipt for every payment that needs one.

- Given a successful payment, when it is recorded, then a document with the next number in sequence is issued
- Given a person with tax data, when the document is issued, then it carries those data and the taxes charged

### Finding and downloading

The system must let a person find their documents and keep a copy.

- Given a person, when they open their billing, then they see their documents in order and can download each one

## Edge cases

- [Issuing] A refund after the document was issued produces a credit note, never an edit of the original
- [Issuing] Two payments at the same moment never receive the same number
- [Finding and downloading] A person changes their tax data: old documents keep the data they were issued with

## Open questions

- [Issuing] Which tax rules, numbering series and required fields apply in your countries?
- [Finding and downloading] Are documents also sent by email, and in which format?
