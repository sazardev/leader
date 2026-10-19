<!-- name: Local disk storage -->
<!-- desc: uploads stored on the server's disk outside the web root, served through the app with checks -->
<!-- for: server backend fullstack selfhosted !mobile -->

## Stack

| File storage | Local disk (a data directory outside the web root and the repo, `UPLOAD_DIR`) | No extra service for a single-server or self-hosted app |

## Project layout

```
src/storage/                   the only module that reads and writes the data directory (put, open, delete)
data/                          UPLOAD_DIR in development (git-ignored); /var/lib/<app>/uploads in production
```

## Conventions

- `UPLOAD_DIR` is configuration; the directory is not inside the repo, the static file root or a container layer (use a volume or bind mount).
- Files are stored under server-generated names (`<uuid>` split into two-level subfolders); the original name lives in the database.
- Files are served through an authenticated route that checks ownership and sets `Content-Type`, `Content-Disposition` and `X-Content-Type-Options: nosniff`.
- Writes go to a temp file in the same directory and are renamed, so a crash never leaves a half file.
- Backups include `UPLOAD_DIR` together with the database dump; a restore is tested.

## Commands

| Disk usage | `du -sh "$UPLOAD_DIR"` |

## Testing

- Tests use a temporary directory as `UPLOAD_DIR` and remove it afterwards.

## Rules for agents

- Resolve every path from a generated id and check it stays inside `UPLOAD_DIR`; never join a user-supplied name into a path (path traversal).
- Never serve the upload directory as static files and never execute anything stored in it.
- Enforce a maximum size and an allow-list of content types before writing a byte.
