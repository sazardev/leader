<!-- name: Cloudinary -->
<!-- desc: hosted images and video with on-the-fly transformations, signed uploads and a CDN -->
<!-- for: web fullstack mobile server !tui -->

## Stack

| File storage | Cloudinary (hosted media library, URL transformations, signed uploads, CDN delivery) | Resizing, formats and delivery handled for us instead of building an image pipeline |

## Project layout

```
src/media/                     the only module that uses the Cloudinary SDK (sign upload, build URL, delete)
.env.example                   CLOUDINARY_URL (cloud name, API key, API secret) as a placeholder
```

## Conventions

- The database stores the `public_id` (and resource type), never the full delivery URL; URLs are built from the `public_id` plus a named transformation.
- Use named transformations / presets (`thumb`, `card`, `hero`) with `f_auto,q_auto` instead of inline size strings scattered in the UI.
- Browser and mobile uploads use a signed upload (signature made on the server with a short timestamp) or an upload preset restricted by folder, format and size.
- Every upload goes to a folder per environment and tenant (`prod/<tenant>/…`); development never writes to the production folder.
- Images get `alt` text from our own data, not from Cloudinary.

## Commands

| Media check | `npx cloudinary-cli admin ping` |

## Testing

- Tests mock the `src/media/` module; no test uploads to a real cloud.

## Rules for agents

- Never expose the API secret to the client; only the cloud name and an upload signature reach it.
- Never use an unsigned preset that accepts any file type or size.
- Never delete assets by prefix without an explicit confirmation step.
