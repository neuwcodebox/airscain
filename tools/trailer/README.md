# Airscain launch trailer

Real Godot gameplay capture, frame-based FFmpeg editing and bilingual graphics.
Game balance and normal runtime behavior are unchanged. The capture fixture
stages paid deployments and two continuous takes; it is not a continuous playthrough.
The 12-second introduction preserves all placed assets. The 48-second raid
pre-spawns its entire attacking force and changes only cameras while time advances.

## Requirements

- Windows, Godot 4.7.2 on PATH, Python 3.10+ with Pillow.
- FFmpeg and ffprobe on PATH. This workstation also supports the installed
  fallback `D:\Utils\ffmpeg-master-latest-win64-gpl\bin`.
- Existing repository NanumSquareB and installed Windows Arial Bold.
- Validated with Python 3.10, Pillow 9.3.0 and FFmpeg
  `N-116271-g9af348bd1a-20240713` on an RTX 3060 (OpenGL Compatibility).
- Music file `build/trailer_v3/assets/volatile-reaction.mp3`, from the official
  source linked in [ASSETS.md](ASSETS.md). Preserve publication attribution.

## Reproduce

Run in the repository root. All commands are offline once music is available.

```powershell
godot --headless --audio-driver Dummy --editor --path . --quit
godot --headless --audio-driver Dummy --path . --script res://tools/trailer/capture.gd --check-only
python tools/trailer/produce.py capture intro --lang ko --seconds 12
python tools/trailer/produce.py capture intro --lang en --seconds 12
python tools/trailer/produce.py capture raid --lang ko --seconds 48
python tools/trailer/edit.py --lang ko
python tools/trailer/edit.py --lang en
python tools/trailer/edit.py --lang ko --clean
python tools/trailer/verify.py --lang ko
python tools/trailer/verify.py --lang en
python tools/trailer/verify.py --lang ko_clean
python tools/trailer/package.py
```

Capture creates a separate 1920×1080 project using directory junctions and
isolates APPDATA. It does not modify the game's project settings or user saves.
Waits for actual effects preparation, then trims pre-roll using the recorded
frame number. Captures run at a fixed 60 simulation/render frames per second;
wall-clock capture speed is not playback speed. Use at most two concurrent takes
on this workstation. Each shot log and event report records actual results.
The HUD-free raid is shared between languages. It retains all events in order,
including normal enemy munition releases, damage, reloads and surviving aircraft.

Editing caches segments using their source timestamp, editorial settings and
artwork. Changed takes or edit code invalidate the appropriate cache. Typography,
darkened end cards, a 0.35-second matched dissolve and three two-frame dark dips
are the only compositing effects. The dissolve uses the outgoing last frame over
the advancing later operation; it does not rewind or replay the battle.
Projectiles, targets, explosions, markers and UI come from the game.

## Delivery and checks

Outputs are under `build/trailer_v3/`; earlier versions remain in
`build/trailer/` and `build/trailer_v2/` for reference:

- `Airscain_Launch_Trailer_KO.mp4`: Korean master, 60 seconds.
- `Airscain_Launch_Trailer_EN.mp4`: English master with English game UI.
- `Airscain_Launch_Trailer_KO_CLEAN.mp4`: same edit without marketing typography;
  original game HUD remains. Attribution must accompany publication.
- `raw/`, `takes/`: original and losslessly preserved audio capture intermediates.
- `edit/*/timeline.json`: source in-points and exact output-frame positions.
- `edit/*/mix.wav`: 48 kHz PCM mix before final loudness normalization.
- `review/`: actual window captures and gameplay telemetry.
- `qa/`: decoded video checks, loudness measurements and contact sheets.

Delivery target is H.264/AAC, 1920×1080, 60 fps, stereo 48 kHz, 3,600 frames.
Verification also checks pre-capture aircraft births, persistent asset IDs and
positions, three placements before the first kill, a wait below three seconds,
per-frame camera continuity outside declared cuts, fourteen raid seconds before first
fire, unresolved pressure at the closing, and monotonically contiguous edit ranges.
Mix targets −16 LUFS integrated and −1.5 dBTP before AAC encoding. Decode checks
and objective audio measurements do not establish perceptual audio quality.
Independent listening and unfamiliar-viewer comprehension remain explicitly
unverified unless separately documented. Do not relabel those as passed.
The dated delivery report is in `docs/TRAILER_DELIVERY.md`.

Read [ASSETS.md](ASSETS.md) for the music credit and omitted unverified recordings.
No uploads, store listings or release dates are part of this production script.
