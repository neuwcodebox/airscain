# Trailer media sources

The footage is captured from Airscain's actual Godot runtime. The production
fixtures stage finite-budget deployments and pre-positioned raids, using unchanged
placement, sensor, weapon, damage and support rules. They are not recordings of
an uninterrupted player session. The edit joins the opening, three deployment stages, one continuous raid including an offscreen ballistic launch and its approach.
The finale plays actual gameplay at normal speed and cuts once to black immediately before impact.
It ends before the ballistic outcome. These are staged operations, not one player session.

## Music

- **Volatile Reaction** — Kevin MacLeod, ISRC USUAN1400039.
- Source: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400039
- Original MP3: https://incompetech.com/music/royalty-free/mp3-royaltyfree/Volatile%20Reaction.mp3
- License: Creative Commons Attribution 4.0 International.
  https://creativecommons.org/licenses/by/4.0/
- Catalog-wide license statement: https://incompetech.com/agent-section/
- Metadata retrieved 2026-09-26 and saved with the downloaded file in
  `build/trailer/assets/music-source.json`.
- Changes: excerpt selection, timing edits, fades, fixed gain and mixing
  with game effects. The original music is not claimed as an original composition.

The video includes a compact music credit. Include this credit with publication:

> “Volatile Reaction” by Kevin MacLeod (incompetech.com).
> Licensed under CC BY 4.0: https://creativecommons.org/licenses/by/4.0/
> Source: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400039
> Edited and mixed for the Airscain trailer.

## Game sound and fonts

- Combat and UI samples: repository CC0 notices in
  `effects/audio/combat/LICENSE.md` and `ui/audio/LICENSE.md`.
- Gun audio: game's existing runtime audio system.
- UAV loops, cruise approach recordings and aircraft flyovers are disabled in
  capture; their source/license records were not sufficient for this release.
- Korean captions: existing `ui/fonts/NanumSquareB.ttf`, rasterized into video.
  NAVER permits commercial use: https://hangeul.naver.com/font
  License: https://help.naver.com/service/11029/contents/18088?lang=ko
  No additional font binary is distributed by this trailer package.
  English title uses locally installed
  Arial Bold as rasterized text; the font binary is not redistributed.
- No remote game footage or generated depictions of unimplemented gameplay.

Current raw and rendered media live in the Git-ignored `build/trailer_v9` directory.
The rejected first version and original music-source record remain in `build/trailer`.

- Contact alert is retained in the opening and disconnected in all later capture takes; combat sounds remain.
- V5: no synthesized siren or other new sound. Music gain stays constant throughout the battle, with opening/ending fades only.
