# Airscain launch trailer — V8

Actual Godot gameplay, frame-based FFmpeg editing, Korean/English graphics and audio mix.
Staged operations use normal paid deployment, sensor, weapon and ballistic rules. This is not one uninterrupted player session.

## Requirements

Windows, Godot on PATH, Python 3.10+ with Pillow, FFmpeg/ffprobe on PATH (the installed `D:/Utils/ffmpeg-master-latest-win64-gpl/bin` fallback is supported). Existing NanumSquareB and Windows Arial Bold are rasterized. The licensed music file is `build/trailer_v8/assets/volatile-reaction.mp3`; see ASSETS.md.

## Reproduce

```powershell
python tools/trailer/produce.py capture intro --lang ko --seconds 21
python tools/trailer/produce.py capture intro --lang en --seconds 21
python tools/trailer/produce.py capture expansion --seconds 6
python tools/trailer/produce.py capture raid --seconds 43
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

The opening follows a UAV close up, then moves smoothly to closer installation views. Expansion tracks across ground-facing sectors; the sea is revealed only by the following continuous camera turn. No fade reveals the fleet.

The opening holds the combat view for four extra seconds so the destroyed UAVs can fall before the camera leaves. The missile finale stays in a close rear chase looking down at the city. It runs at normal simulation and playback speed, then cuts once to black immediately before the recorded impact event. There is no slow motion, held frame or blinking montage. Music gain remains constant; no siren or warning caption is added.

## Delivery and checks

Current output: `build/trailer_v8/`. Previous versions remain in their directories.

- `Airscain_Launch_Trailer_KO.mp4`, `EN.mp4` and `KO_CLEAN.mp4`: 1920×1080, 60fps H.264/AAC stereo. CLEAN removes marketing typography, retaining actual game HUD and editorial fades.
- `review/`: actual window captures and event/camera records.
- `qa/`: full decoded-frame, loudness and story checks; contact sheets.
- `delivery/`: thumbnails, separate audio stems, publication credits and SHA-256 manifest.

Verification checks real placements, rapid first fire, increasing persistent asset counts, zero later contact sounds, preexisting fleet plus offscreen ballistic launch, genuine ballistic reentry, normal-speed rear chase and one pre-impact blackout without resolution, exact source ranges and the dynamically computed output frame count. Intentional expansion fades and ending black cards are allowed explicitly. Source trimming excludes the one pre-roll display frame before the first directed frame. Mastering uses one static gain, aiming at −16 LUFS when the −1.5 dBTP peak ceiling permits it; no dynamic normalization. Objective measurements do not establish perceptual audio quality. Actual listening remains separately unverified unless documented.

See `docs/TRAILER_STORYBOARD.md`, `docs/TRAILER_DELIVERY.md` and ASSETS.md. No uploads or store changes are included.
