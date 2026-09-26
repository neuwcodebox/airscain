"""Collect publication credits, thumbnails, stems and reproducibility hashes."""
from pathlib import Path
import hashlib
import json
import shutil
from edit import run
from produce import ROOT, OUT


def package() -> None:
    delivery=OUT/'delivery';delivery.mkdir(exist_ok=True)
    shutil.copyfile(ROOT/'tools/trailer/ASSETS.md',delivery/'PUBLICATION_CREDITS.md')
    shutil.copyfile(ROOT/'tools/trailer/README.md',delivery/'PRODUCTION_README.md')
    shutil.copyfile(ROOT/'docs/TRAILER_DELIVERY.md',delivery/'QUALITY_REVIEW.md')
    for language in ['KO','EN']:
        source=OUT/f'Airscain_Launch_Trailer_{language}.mp4'
        run(['-ss','22','-i',str(source),'-frames:v','1','-q:v','1',
             str(delivery/f'Thumbnail_{language}.jpg')])
    run(['-i',str(OUT/'edit/ko/assembled.mkv'),'-vn','-af',
         'volume=0.70,afade=t=out:st=52.4:d=0.25','-t','60','-ar','48000',
         '-c:a','pcm_s24le',str(delivery/'Game_SFX.wav')])
    gain="if(lt(t,18),0.10,if(lt(t,44),0.20,if(lt(t,52.5),0.27,0.025)))"
    run(['-i',str(OUT/'assets/volatile-reaction.mp3'),'-af',
         f"atrim=0:60,asetpts=PTS-STARTPTS,volume='{gain}':eval=frame,afade=t=in:d=0.25,afade=t=out:st=58:d=2",
         '-t','60','-ar','48000','-c:a','pcm_s24le',str(delivery/'Music_Edit.wav')])
    sources=list((ROOT/'tools/trailer').glob('*.*'))+list(OUT.glob('Airscain*.mp4'))
    sources += list((OUT/'review').glob('*.json'))+[OUT/'assets/volatile-reaction.mp3']
    sources += [ROOT/'docs/TRAILER_DELIVERY.md',ROOT/'docs/TRAILER_STORYBOARD.md']
    manifest={}
    for path in sources:
        if not path.is_file():continue
        digest=hashlib.sha256()
        with path.open('rb') as file:
            for chunk in iter(lambda:file.read(1048576),b''):digest.update(chunk)
        manifest[str(path.relative_to(ROOT))]={'bytes':path.stat().st_size,'sha256':digest.hexdigest()}
    (delivery/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(delivery)


if __name__=='__main__':package()
