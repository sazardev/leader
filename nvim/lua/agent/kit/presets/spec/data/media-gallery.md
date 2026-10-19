<!-- name: Media library -->
<!-- desc: a library of images, video and files: upload, folders, metadata, previews, where used, safe deletion -->
<!-- for: all -->
<!-- needs: uploads -->
<!-- tech: storage database search -->
<!-- design: file-upload-ui data-tables search-and-filters empty-states -->

## Requirements

### Library

The system must keep every uploaded file where people can find and organise it.

- Given a file, when it is uploaded, then it appears in the library with its name, type, size, date and who uploaded it
- Given the library, when a person creates folders or tags and puts files in them, then they can browse by them
- Given the library, when a person searches by name, type or tag, then only the matching files are listed

### Previews and details

The system must let people see what a file is before using it.

- Given an image or video, when it is listed, then a preview is shown
- Given a file, when a person opens it, then they see its metadata and can edit its name and description

### Using and removing

The system must know where a file is used and never break what depends on it.

- Given a file, when it is used in some content, then the library shows where
- Given a file that is in use, when someone deletes it, then they are told where it is used and must confirm or choose a replacement

## Edge cases

- [Library] The same file is uploaded twice: the person is told and chooses to reuse the existing one or keep both
- [Previews and details] A file is corrupt or a preview cannot be made: a generic icon is shown, the file stays downloadable
- [Using and removing] Two people delete or replace the same file at the same moment: one result, no broken link left behind
- [Library] A file name has odd characters or is very long: it is kept readable and downloads with a valid name
- [Using and removing] A deleted file can be recovered for the period below

## Open questions

- [Library] Which file types and sizes are allowed, and is there a storage limit per person or account?
- [Using and removing] Is a deleted file kept for a while, and who can restore or empty the trash?
- [Library] Can files be private, shared with some people or public by address?
