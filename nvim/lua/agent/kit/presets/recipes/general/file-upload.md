<!-- name: File upload -->
<!-- desc: validated upload, storage per STACK.md, safe names, progress, authorized download and cleanup -->
<!-- for: server+ui -->
<!-- input: what | What is uploaded (e.g. avatar, invoice PDF, project attachments) -->
<!-- input: limits | Allowed types and size (e.g. PNG/JPEG/WebP, up to 5 MB, one file) -->

# Recipe: upload of {{what}}

Limits: {{limits}}.

## Make

- An upload operation on the project's API that accepts multipart (or a signed direct upload when STACK.md's storage is object storage) for {{what}}.
- Validation on the server: size, count and type, checking the content (magic bytes) and not only the extension or the declared type.
- Storage as STACK.md says (local disk behind one storage module, S3-compatible bucket, the platform's storage), with a generated name (a random id plus a safe extension); the original name kept only as metadata. A record in the database with owner, size, type and storage key.
- Download or serving through an operation that checks authorization first (or short-lived signed URLs); correct content type, `Content-Disposition` for downloads, `X-Content-Type-Options: nosniff`.
- The UI: a picker with drag and drop, a preview when it is an image, progress, cancel, and clear errors for too big, wrong type and network failure.
- Cleanup: deleting the owner or replacing the file removes the stored object; unfinished or orphaned uploads are removed by a periodic job.

## Rules

- Never build a path from user input; no path separators or `..` in any name; files are never executed or served from a public code folder.
- The size limit is enforced while streaming, not after buffering the whole file.
- Errors map in one place: too large 413, unsupported type 415, no permission 403, missing 404.
- Follow the existing storage and API code: naming, config, error helper.

## Tests

- A valid file is stored and downloadable by its owner; another user gets 403.
- Rejected: too large, wrong type with a faked extension, an empty file, a hostile name (`../x`).
- Replacing or deleting removes the old object; the UI shows progress and each error state.
