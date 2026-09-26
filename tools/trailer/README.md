# Airscain launch trailer — V5

Actual Godot gameplay, frame-based FFmpeg editing, Korean/English graphics and audio mix.
Staged operations use normal paid deployment, sensor, weapon and ballistic rules. This is not one uninterrupted player session.

## Requirements

Windows, Godot on PATH, Python 3.10+ with Pillow, FFmpeg/ffprobe on PATH (the installed `D:/Utils/ffmpeg-master-latest-win64-gpl/bin` fallback is supported). Existing NanumSquareB and Windows Arial Bold are rasterized. The licensed music file is `build/trailer_v5/assets/volatile-reaction.mp3`; see ASSETS.md.

## Reproduce

```powershell
python tools/trailer/produce.py capture intro --lang ko --seconds 12
python tools/trailer/produce.py capture intro --lang en --seconds 12
python tools/trailer/produce.py capture expansion --seconds 6
python tools/trailer/produce.py capture raid --seconds 31.9
python tools/trailer/edit.py --lang ko
python tools/trailer/edit.py --lang en
python tools/trailer/edit.py --lang ko --clean
python tools/trailer/verify.py --lang ko
python tools/trailer/verify.py --lang en
python tools/trailer/verify.py --lang ko_clean
python tools/trailer/package.py
```

Capture creates an isolated 1920×1080 project using junctions and separate APPDATA. It waits for effect preparation and trims pre-roll using the reported first movie frame. Capture uses 60 simulated frames per second regardless of wall-clock speed. At most two concurrent captures are recommended on the RTX 3060 workstation.

Opening icons are the game's existing tactical symbols, enlarged for readability. Contact audio remains in the opening but the track-created audio signal is disconnected in later takes. Unknown-license flyover recordings are excluded. No warning siren or missile caption is used.

The edit uses intro 0–12, expansion 0–6, raid 6–31.9, then 7.6 seconds of dark ending cards. The same raid includes 100 ordinary threats and a preexisting ballistic missile arriving at reentry around source second 30. The three rear chase views show the same ongoing battle below the missile. Two exact nine-frame black cuts separate 0.7/0.5/0.4-second glimpses. Time continues through black frames; no separate operation, frozen missile, slow motion or resolution is shown. Music uses constant gain throughout, with opening/ending fades only.

## Delivery and checks

Current output: `build/trailer_v5/`. Previous versions remain in their directories.

- `Airscain_Launch_Trailer_KO.mp4`, `EN.mp4` and `KO_CLEAN.mp4`: 51.5s, 1920×1080, 60fps H.264/AAC stereo. CLEAN removes marketing typography, retaining actual game HUD and editorial fades.
- `review/`: actual window captures and event/camera records.
- `qa/`: full decoded-frame, loudness and story checks; contact sheets.
- `delivery/`: thumbnails, separate audio stems, publication credits and SHA-256 manifest.

Verification checks real placements, rapid first fire, increasing persistent asset counts, zero later contact sounds, preexisting raid threats, genuine ballistic reentry without resolution, exact source ranges and 3,090 output frames. Intentional expansion fades and ending black cards are allowed explicitly. Mastering uses one static gain, aiming at −16 LUFS when the −1.5 dBTP peak ceiling permits it; no dynamic normalization. Objective measurements do not establish perceptual audio quality. Actual listening remains separately unverified unless documented.

See `docs/TRAILER_STORYBOARD.md`, `docs/TRAILER_DELIVERY.md` and ASSETS.md. No uploads or store changes are included.
