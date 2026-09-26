# Airscain launch trailer — V6

Actual Godot gameplay, frame-based FFmpeg editing, Korean/English graphics and audio mix.
Staged operations use normal paid deployment, sensor, weapon and ballistic rules. This is not one uninterrupted player session.

## Requirements

Windows, Godot on PATH, Python 3.10+ with Pillow, FFmpeg/ffprobe on PATH (the installed `D:/Utils/ffmpeg-master-latest-win64-gpl/bin` fallback is supported). Existing NanumSquareB and Windows Arial Bold are rasterized. The licensed music file is `build/trailer_v6/assets/volatile-reaction.mp3`; see ASSETS.md.

## Reproduce

```powershell
python tools/trailer/produce.py capture intro --lang ko --seconds 12
python tools/trailer/produce.py capture intro --lang en --seconds 12
python tools/trailer/produce.py capture expansion --seconds 6
python tools/trailer/produce.py capture raid --seconds 47
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

The edit uses intro 0–12, expansion 0–6, raid 6–47, then 7.6 seconds of ending cards. Expansion holds the camera fixed across all three asset stages. The final expansion stage and the sea reveal share one camera pose, with no fade at their join. The combat section lasts 26 seconds. The fleet is pre-positioned; the ballistic missile launches offscreen during the same operation, using a deterministic target seed and normal flight/combat rules.

The missile first appears continuously for 2.5 seconds. Just before impact, the entire runtime slows from normal time to 0.3%, producing actual newly rendered motion rather than interpolated or frozen frames. Seven progressively shorter black cuts accelerate the editing rhythm. The take ends before impact or interception. Marketing captions are removed from the opening and expansion. Only a final command invitation, game title, genre and play prompt remain. Music gain is constant throughout.

## Delivery and checks

Current output: `build/trailer_v6/`. Previous versions remain in their directories.

- `Airscain_Launch_Trailer_KO.mp4`, `EN.mp4` and `KO_CLEAN.mp4`: 66.6s, 1920×1080, 60fps H.264/AAC stereo. CLEAN removes marketing typography, retaining actual game HUD and editorial fades.
- `review/`: actual window captures and event/camera records.
- `qa/`: full decoded-frame, loudness and story checks; contact sheets.
- `delivery/`: thumbnails, separate audio stems, publication credits and SHA-256 manifest.

Verification checks real placements, rapid first fire, increasing persistent asset counts, zero later contact sounds, preexisting fleet plus offscreen ballistic launch, genuine ballistic reentry and near-impact slow motion without resolution, exact source ranges and 3,996 output frames. Intentional expansion fades and ending black cards are allowed explicitly. Mastering uses one static gain, aiming at −16 LUFS when the −1.5 dBTP peak ceiling permits it; no dynamic normalization. Objective measurements do not establish perceptual audio quality. Actual listening remains separately unverified unless documented.

See `docs/TRAILER_STORYBOARD.md`, `docs/TRAILER_DELIVERY.md` and ASSETS.md. No uploads or store changes are included.
