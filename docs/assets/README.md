# Assets

The repository banner and the GitHub social preview are rendered from the HTML files in this folder, with the docs'
self-hosted Geist fonts and the flat palette. They are plain images in the repository; the HTML sources are here so a
change is reproducible.

| File | Use |
|---|---|
| `banner.html` → `banner.png` | the README header (1600×400, rendered at 2× = 3200×800) |
| `social-preview.html` → `social-preview.png` | GitHub **Settings → Social preview** (1280×640, rendered at 2× = 2560×1280) |

Rendering (no image editor needed):

```sh
python3 -m http.server 8766 --directory docs
/opt/helium-browser-bin/helium --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=1600,400 --virtual-time-budget=3000 \
  --screenshot=docs/assets/banner.png http://127.0.0.1:8766/assets/banner.html
/opt/helium-browser-bin/helium --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=1280,640 --virtual-time-budget=3000 \
  --screenshot=docs/assets/social-preview.png http://127.0.0.1:8766/assets/social-preview.html
```

Any Chromium (Helium, Chrome) works; the exact binary is the one used on the machine that made the assets. The social
preview has no API: upload `social-preview.png` in the repository settings. The site serves `docs/` as-is, so the images
are also available at `/assets/…`.

The favicons (`apple-touch-icon.png`, `icon-192.png`) live one level up in `docs/`; the app's icons and the SVG source are
in `app/assets/`.
