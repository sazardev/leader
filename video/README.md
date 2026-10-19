# The video

A commercial for Leader: a scripted, frame-exact recording of the editor at work (completion, the inline agent,
the build kit, commits, release, themes), in the landing page's design. Nothing is screen-captured: every frame is drawn
from time alone, so the output is identical on every run and any change to the copy is a re-render away.

## Render

```sh
node video/render.mjs                      # → video/out/leader.mp4 (1920×1080, 30 fps)
node video/render.mjs --serve              # preview in a browser: Space play/pause, ←/→ 1 s, Shift+←/→ scene
node video/render.mjs --scene lens         # one scene only (ids in story.js)
node video/render.mjs --still 41.5         # one PNG; --stills 2,8,12 for several
node video/render.mjs --fps 60 --scale 2   # 60 fps, 3840×2160
node video/render.mjs --remux              # redo only the sound on the last render (seconds)
node video/render.mjs --audio-only         # write out/soundtrack.wav (the preview plays it in sync)
node video/render.mjs --music track.mp3    # a music file instead of the generated score
node video/render.mjs --no-audio           # silent
node video/render.mjs --theme t:nord       # whole video in a terminal palette (ids from the landing's theme picker)
```

Needs Node 22+ (built-in WebSocket), Chromium/Chrome (`--chromium <path>` or `CHROMIUM=` if it is not on PATH) and
ffmpeg with libx264. No npm packages.

## Sound

Three layers, all from the same timeline as the picture (`engine.js` turns every API call into audio cues):

- **Keys**: a recorded mechanical keyboard (Holy Panda, MIT, `audio/keys`) for every character typed and every key
  chip, with release clicks and small variations; the music steps back while you type.
- **Effects**: synthesized UI sounds: which-key, the agent starting, a proposal, accept, toasts, panels, whooshes.
- **Music**: an original score (`audio.mjs`) whose sections start on scene cuts, with risers and impacts on the drops.
  Edit `audio` in `story.js`: sections, tempo, levels, cue kinds to mute, or a music file.

The mix is normalized to -14 LUFS / -1.5 dBTP (two-pass EBU R128). Credits: `audio/CREDITS.md`.

## Edit

- **Copy**: every line the viewer reads is in `TEXT` at the top of `story.js`.
- **Scenes**: the rest of `story.js`, one entry per scene, written with the small API documented at its top
  (`v.type`, `v.keys("␣ a f")`, `v.diff`, `v.zoom`, `v.card`…). Each call happens at the current time and moves it.
  `pace` scales every pause and keystroke.
- **Look**: the landing's stylesheet, which-key menus (generated from the real keymaps), the mini project `PROJ`, the
  terminal palettes and the dashboard art are read from `docs/index.html` at load time, so the video follows the site.
  `video.css` only adds the stage, captions and full-screen cards; `engine.js` holds the timeline and a port of the
  landing's editor mock (keep it in sync when the mock changes).
- Nothing in the page may animate on its own (no CSS transitions or keyframes): motion is computed from the frame time
  in `engine.js`, which is what keeps renders deterministic.
