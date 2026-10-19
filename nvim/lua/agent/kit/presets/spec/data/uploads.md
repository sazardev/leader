<!-- name: File uploads -->
<!-- desc: uploading files and images: limits, progress, previews, failures, who can see them -->
<!-- for: all -->
<!-- tech: storage -->
<!-- design: file-upload-ui -->

## Requirements

### Uploading

The system must let a person attach files, with their progress and their result.

- Given a file within the limits, when they upload it, then they see its progress and then the file attached with its name and size
- Given a file over the size limit or of a type not allowed, when they choose it, then it is refused before uploading with the limit it breaks
- Given an upload that fails or loses the connection, when it happens, then they see it failed and can retry without choosing the file again

### Viewing and downloading

The system must show and give back the files people uploaded, only to those allowed.

- Given an image, when it is shown, then a preview of a fitting size loads first
- Given a file, when someone allowed opens it, then they can download it with its original name
- Given a file, when someone not allowed opens its link, then it is refused, also when the link was shared

### Removing

The system must let the people allowed to do so remove a file.

- Given an attached file, when it is removed, then it disappears from where it was attached and its storage is freed
- Given a removed file, when its old link is opened, then it says the file is gone

## Edge cases

- [Uploading] A file whose type does not match its content (a renamed executable) is refused
- [Uploading] Two files with the same name: both are kept
- [Viewing and downloading] Photos carry location data: it is removed before others can see them

## Open questions

- [Uploading] Which file types and what maximum size?
- [Viewing and downloading] Are files private to their workspace, shared by link, or public?
