# Leader brand kit

Marketing images for every platform, in the landing's design system (flat, square, Geist, the palette), plus the logo.
Nothing is drawn by hand: pages in HTML are rendered by Chromium at the exact pixel size of each platform, so a copy
change or a new piece is a re-render away.

```sh
node brand/shots.mjs      # 1. real screenshots of the editor → brand/shots/ (the video's page, paused on a moment)
node brand/render.mjs     # 2. everything → brand/out/ (300+ images, SVG logos, favicon.ico, contact sheets, USAGE.md)
node brand/render.mjs --only square         # one folder (or any dir/name substring: --only 20ms, --only carousel/tips)
node brand/render.mjs --list                # the catalog
```

Needs Node 22+, Chromium/Chrome (`CHROMIUM=/path` if it is not on PATH) and ffmpeg (only for `favicon.ico`). No npm packages.
The render checks every text box and prints a warning when a headline gets too small or runs out of its box.

## What is in `out/`

- `landscape/` `link-preview/` `square/` `portrait/` `story/` `pinterest/`: every piece in every size (`copy.js` has the list).
- `carousel/{launch,agent,tips}/`: Instagram / LinkedIn 4:5 slide sets with a page indicator.
- `banners/` `social/`: X, LinkedIn, Facebook, YouTube, GitHub banners and avatars.
- `wallpapers/{desktop,phone,ultrawide,4k}/`: the wallpaper collection: 7 compositions (`ghost` `grid` `braille` `keys` `dots` `minimal` `editor`) and 4 with words (`phrase` programmer maxims, `lang` one programming language with a snippet and its tools, `term` a glossary entry, `cheat` a key cheat sheet from the real menus), in gruvbox and the terminal palettes, dark and light. The lists are `wallpapers`, `wpPhrases`, `wpLangs`, `wpTerms` and `wpCheats` in `copy.js`.
- `logo/`: the mark on colors and transparent, lockups, the dot-matrix wordmark, favicons, `svg/`, `brand-board.png`.
- `catalog-*.png`: contact sheets. `USAGE.md`: which size goes where, plus the text to post with each piece.

## Edit

- **Copy** (headlines, subs, captions, sizes and where they are used): `copy.js`. Pieces have a `kind`
  (`poster` `shot` `stat` `rows` `keys` `install` `themes` `duo`), a background (`bg` `deep` `yellow` `aqua` `green`, or
  `theme: "light"`) and, for `shot`, a screenshot id from `shots.mjs`.
- **Templates**: `brand.js` (one design per kind, banners, wallpapers, logos, the brand board). `brand.css` holds the
  kit's classes; the palette, fonts and flat rules come from `docs/index.html` at load time, so the kit follows the site.
- **Screenshots**: `shots.mjs` (`SHOTS`: a scene of `video/story.js` plus an offset in seconds, optionally a terminal palette).
  `--probe 12,16.4` saves candidates at those seconds to pick a moment.
- **The mark and the dot font**: `dots.js`. The mark is an N of dots grouped in braille cells of 2×4; numerals and the
  `LEADER` wordmark use a 5×7 dot-matrix with the unlit grid faintly showing. Dots are the only round shape in the system.

`shots/` and `out/` are generated and git-ignored.
