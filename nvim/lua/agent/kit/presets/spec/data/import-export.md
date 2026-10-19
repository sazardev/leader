<!-- name: Import and export -->
<!-- desc: CSV/JSON import with a preview and row errors, exports of what the user owns -->
<!-- for: all -->
<!-- tech: jobs storage -->
<!-- design: file-upload-ui forms -->

## Requirements

### Import

The system must let a person import their data from a file, check it first, and see what failed.

- Given a file in a supported format, when they import it, then they see a preview with how many rows will be added and which are invalid, before anything is saved
- Given the preview, when they confirm, then the valid rows are saved and a report lists every row that failed and why
- Given a file in the wrong format or with missing columns, when they choose it, then it is refused with what is expected

### Export

The system must let a person export their data to a file.

- Given a list, when they export it, then they get a file with every item the list shows (filters applied), not only the page on screen
- Given a large export, when it is requested, then it runs in the background and they are told when the file is ready
- Given an export, when it is made, then it contains only data the person is allowed to see

## Edge cases

- [Import] The same file imported twice: the duplicates are detected and the person chooses to skip or update them
- [Import] Text in another encoding or with a different separator is detected or can be chosen
- [Export] A value that a spreadsheet would run as a formula (starting with =, +, -, @) is written so it cannot run

## Open questions

- [Import] Which formats (CSV, Excel, JSON) and which data can be imported?
- [Export] Which formats, and is there a full export of the account (for leaving the service)?
