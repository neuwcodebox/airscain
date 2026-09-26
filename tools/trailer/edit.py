"""Frame-based editorial conform, caption artwork and loudness-controlled mix.

No rendered frame fabricates game UI, projectiles, impacts or weapon effects.
Only typography, selective darkening, a matched dissolve and editorial dips are added.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont
from produce import ROOT, OUT, FFMPEG

FONT = ROOT / 'ui/fonts/NanumSquareB.ttf'
LATIN = Path('C:/Windows/Fonts/arialbd.ttf')


def run(args: list[str]) -> None:
    subprocess.run([FFMPEG, '-y', '-hide_banner', '-loglevel', 'error', *args], check=True)


def art(language: str) -> dict[str, Path]:
    folder = OUT / 'graphics'
    folder.mkdir(exist_ok=True)
    words = {
        'build': '방공망을 설계하라.' if language == 'ko' else 'BUILD YOUR AIR DEFENSE.',
        'expand': '방어선을 확장하라.' if language == 'ko' else 'EXPAND YOUR DEFENSE.',
        'call': '이 도시에는 당신이 필요합니다.' if language == 'ko' else 'THIS CITY NEEDS YOU.',
    }
    files = {}
    for key, title in words.items():
        image = Image.new('RGBA', (1920,1080))
        draw = ImageDraw.Draw(image)
        if key != 'call':
            for y in range(700,1080):
                opacity = round(175*((y-700)/380)**1.2)
                draw.line((0,y,1920,y),fill=(3,12,18,opacity))
            left=500 if key=='build' else 96
            draw.rectangle((left+4,855,left+72,860),fill=(255,183,66,255))
            draw.text((left,885),title,font=ImageFont.truetype(str(FONT if language=='ko' else LATIN),58),fill=(245,248,249),stroke_width=1)
        else:
            font = ImageFont.truetype(str(FONT if language=='ko' else LATIN),62)
            width=draw.textbbox((0,0),title,font=font)[2]
            draw.text(((1920-width)/2,491),title,font=font,fill=(245,248,249))
        target=folder/f'{key}_{language}.png'
        image.save(target);files[key]=target
    image=Image.new('RGBA',(1920,1080));draw=ImageDraw.Draw(image)
    def centered(text: str,y: int,font: ImageFont.FreeTypeFont,color: tuple):
        width=draw.textbbox((0,0),text,font=font)[2]
        draw.text(((1920-width)/2,y),text,font=font,fill=color)
    centered('AIR DEFENSE  /  REAL-TIME STRATEGY',358,ImageFont.truetype(str(LATIN),25),(157,188,199))
    centered('AIRSCAIN',412,ImageFont.truetype(str(LATIN),142),(244,247,248))
    draw.rectangle((909,597,1011,600),fill=(255,181,70))
    centered('지금 플레이하세요' if language=='ko' else 'PLAY NOW',640,
             ImageFont.truetype(str(FONT if language=='ko' else LATIN),43),(255,192,94))
    centered('Music: Volatile Reaction — Kevin MacLeod (incompetech.com) · CC BY 4.0 · Edited',1000,
             ImageFont.truetype(str(FONT),21),(177,190,196))
    target=folder/f'end_{language}.png';image.save(target);files['end']=target
    return files


def timeline(language: str) -> list[dict]:
    # Every source frame advances once. Camera changes happen inside the same raid.
    def row(shot,start,end,caption=None,dark=0,dip=False):
        return dict(shot=shot,lang=language if shot=='intro' else 'ko',
                    start=start,frames=round((end-start)*60),caption=caption,dark=dark,dip=dip)
    rows=[row('intro',0,1),row('intro',1,6,'build'),
          row('intro',6,10),row('intro',10,12)]
    cuts=[0,4,6,10,14,18,22,26,29,32,33.5,34.75,35.75,36.5,37.25,38,41,43,48]
    for start,end in zip(cuts,cuts[1:]):
        caption='expand' if start==0 else 'call' if start==41 else 'end' if start==43 else None
        rows.append(row('raid',start,end,caption,
                        dark=.70 if caption=='call' else .76 if caption=='end' else 0,
                        dip=start in [32,34.75,36.5]))
    assert sum(r['frames'] for r in rows)==3600
    clock=0
    for r in rows:
        r['timeline_start']=clock;clock+=r['frames']
    return rows


def render(language: str, no_text: bool=False) -> Path:
    graphics=art(language)
    label=language if not no_text else language+'_clean'
    work=OUT/'edit'/label;work.mkdir(parents=True,exist_ok=True)
    rows=timeline(language)
    (work/'timeline.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    bridge=work/'bridge-from.png'
    run(['-ss',str(12-1/60),'-i',str(OUT/'takes'/f'intro_{language}.mkv'),
         '-frames:v','1',str(bridge)])
    segments=[]
    for i,r in enumerate(rows):
        target=work/f'{i:02d}.mkv';segments.append(target)
        source=OUT/'takes'/f'{r["shot"]}_{r["lang"]}.mkv'
        if not source.exists(): raise FileNotFoundError(source)
        probe=str(Path(FFMPEG).with_name('ffprobe.exe'))
        source_length=float(subprocess.check_output([probe,'-v','error','-show_entries',
            'format=duration','-of','default=noprint_wrappers=1:nokey=1',str(source)],text=True))
        if r['start']+r['frames']/60>source_length+0.02:
            raise ValueError(f'Source take too short for edit: {source.name}')
        signature=hashlib.sha256(json.dumps(r,sort_keys=True).encode()+
            str(source.stat().st_mtime_ns).encode()+Path(__file__).read_bytes()+
            (bridge.read_bytes() if r['shot']=='raid' and r['start']==0 else b'')+
            (graphics[r['caption']].read_bytes() if r['caption'] and not no_text else b'')).hexdigest()
        stamp=target.with_suffix('.sha256')
        if target.exists() and stamp.exists() and stamp.read_text()==signature: continue
        duration=r['frames']/60
        args=['-ss',str(r['start']),'-i',str(source)]
        filters=['fps=60','setsar=1']
        if r['dark']:filters.append(f'drawbox=c=0x020b12@{r["dark"]}:t=fill')
        if r['dip']:filters.append(f'fade=t=out:st={duration-2/60}:d={2/60}')
        video=','.join(filters)
        graph=[f'[0:v]{video}[v]'];base='v';input_index=1
        if r['shot']=='raid' and r['start']==0:
            # The outgoing last frame fades over the advancing later operation.
            # Matching the camera pose makes this a readable passage of time.
            args+=['-loop','1','-i',str(bridge)]
            graph += [f'[{input_index}:v]format=rgba,fade=t=out:d=0.35:alpha=1[previous]',
                      '[v][previous]overlay=0:0:shortest=1[bridge]']
            base='bridge';input_index+=1
        if r['caption'] and not no_text:
            args+=['-loop','1','-i',str(graphics[r['caption']])]
            graph += [f'[{input_index}:v]format=rgba,fade=t=in:d=0.18:alpha=1,fade=t=out:st={duration-.18}:d=0.18:alpha=1[title]',
                      f'[{base}][title]overlay=0:0:shortest=1[out]']
            base='out'
        args+=['-filter_complex',';'.join(graph),'-map',f'[{base}]','-map','0:a:0']
        args+=['-t',str(duration),'-frames:v',str(r['frames']),'-c:v','libx264','-preset','fast',
               '-crf','16','-pix_fmt','yuv420p','-af',f'afade=t=in:d=0.012,afade=t=out:st={max(0,duration-.03)}:d=0.03',
               '-ar','48000','-c:a','pcm_s24le',str(target)]
        run(args)
        stamp.write_text(signature)
        print(f'EDIT {label} {i+1}/{len(rows)}',flush=True)
    listing=work/'concat.txt'
    listing.write_text(''.join("file '"+p.as_posix()+"'\nduration "+str(r['frames']/60)+"\n"
                              for p,r in zip(segments,rows)),encoding='utf-8')
    assembled=work/'assembled.mkv'
    run(['-f','concat','-safe','0','-i',str(listing),'-c','copy',str(assembled)])
    mix=work/'mix.wav'
    # Level automation follows the drama; output limiting does not imply listening QA.
    expression="if(lt(t,12),0.09,if(lt(t,26),0.065,if(lt(t,38),0.16,if(lt(t,52.5),0.25,0.035))))"
    graph=f"[0:a]volume=0.70,afade=t=out:st=52.4:d=0.25[sfx];[1:a]atrim=0:60,asetpts=PTS-STARTPTS,volume='{expression}':eval=frame,afade=t=in:d=0.25,afade=t=out:st=58:d=2[m];[sfx][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.90:level=0[out]"
    run(['-i',str(assembled),'-i',str(OUT/'assets/volatile-reaction.mp3'),'-filter_complex',graph,'-map','[out]','-t','60','-ar','48000','-c:a','pcm_s24le',str(mix)])
    # Two-pass normalization for a predictable web master.
    measure=subprocess.run([FFMPEG,'-hide_banner','-i',str(mix),'-af','loudnorm=I=-16:TP=-1.5:LRA=9:print_format=json','-f','null','NUL'],capture_output=True,text=True,check=True)
    block=measure.stderr[measure.stderr.rfind('{'):measure.stderr.rfind('}')+1]
    metrics=json.loads(block)
    (work/'loudness-input.json').write_text(json.dumps(metrics,indent=2))
    norm=f'loudnorm=I=-16:TP=-1.5:LRA=9:measured_I={metrics["input_i"]}:measured_TP={metrics["input_tp"]}:measured_LRA={metrics["input_lra"]}:measured_thresh={metrics["input_thresh"]}:offset={metrics["target_offset"]}:linear=true'
    final=OUT/f'Airscain_Launch_Trailer_{label.upper()}.mp4'
    run(['-i',str(assembled),'-i',str(mix),'-map','0:v:0','-map','1:a:0','-c:v','copy','-af',norm,'-ar','48000','-c:a','aac','-b:a','320k','-t','60','-movflags','+faststart',str(final)])
    print(f'MASTER {final}',flush=True)
    return final


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--lang',choices=['ko','en'],default='ko');p.add_argument('--clean',action='store_true')
    options=p.parse_args();render(options.lang,options.clean)
