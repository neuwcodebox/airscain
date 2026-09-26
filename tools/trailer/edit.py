"""Frame-based editorial conform, caption artwork and loudness-controlled mix.

No rendered frame fabricates game UI, projectiles, impacts or weapon effects.
Only typography, selective darkening and two-frame editorial dips are added.
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
        'raids': '공습은 멈추지 않는다.' if language == 'ko' else "THE RAIDS DON'T STOP.",
        'decoy': '적의 공격을 유인하라.' if language == 'ko' else 'DRAW ENEMY FIRE.',
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


def fire_start(shot: str,language: str) -> float:
    meta=OUT/'review'/f'{shot}_{language}.json'
    data=json.loads(meta.read_text(encoding='utf-8'))
    fires=[e['frame']/60 for e in data['events'] if e['event']=='fire' and e.get('asset')==shot]
    if not fires:
        raise ValueError(f'No recorded weapon fire: {shot}_{language}')
    return max(0,fires[0]-.3)


def timeline(language: str) -> list[dict]:
    # HUD-free hero takes are language-neutral. HUD shots are captured in both languages.
    def row(shot,start,duration,caption=None,lang=None,dark=0,dip=False):
        return dict(shot=shot,lang=lang or language,start=start,frames=round(duration*60),caption=caption,dark=dark,dip=dip)
    def hero(shot,duration,start=None,dip=False):
        return row(shot,fire_start(shot,'ko') if start is None else start,duration,lang='ko',dip=dip)
    rows=[
        row('opening',1,3),
        row('placement',1.2,4,'build'),
        row('network',0.4,3,'build'),
        hero('missile_battery',4),
        hero('close_in_gun',4),
        row('overview',4,6,'raids'),
        row('radar',2,1.5),
        hero('long_range_missile',2),
        hero('missile_battery',2,start=3.4),
        hero('short_range_missile',2),
        hero('high_energy_laser',2),
        hero('high_power_microwave',2),
        hero('interceptor_drone_defense',2),
        hero('close_in_gun',1.5,start=6),
        row('support',16,2),
        row('radar_decoy',2.75,1.5,'decoy',lang='ko'),
        row('weapon_decoy',10,1.5,'decoy',lang='ko'),
        hero('long_range_missile',1.25,start=5),
        hero('missile_battery',1,start=4,dip=True),
        hero('short_range_missile',.75,start=10.5),
        hero('high_energy_laser',.75,start=5,dip=True),
        hero('high_power_microwave',.75,start=6.35),
        hero('interceptor_drone_defense',.5,start=4.25),
        hero('close_in_gun',.5,start=7,dip=True),
        row('crisis',10.5,.5),
        row('crisis',11,3),
        row('closing',7,2,'call',dark=.73,lang='en'),
        row('closing',9,5,'end',dark=.78,lang='en'),
    ]
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
            (graphics[r['caption']].read_bytes() if r['caption'] and not no_text else b'')).hexdigest()
        stamp=target.with_suffix('.sha256')
        if target.exists() and stamp.exists() and stamp.read_text()==signature: continue
        duration=r['frames']/60
        args=['-ss',str(r['start']),'-i',str(source)]
        filters=['fps=60','setsar=1']
        if r['dark']:filters.append(f'drawbox=c=0x020b12@{r["dark"]}:t=fill')
        if r['dip']:filters.append(f'fade=t=out:st={duration-2/60}:d={2/60}')
        video=','.join(filters)
        if r['caption'] and not no_text:
            args+=['-loop','1','-i',str(graphics[r['caption']])]
            graph=f'[0:v]{video}[v];[v][1:v]overlay=0:0:shortest=1[out]'
            args+=['-filter_complex',graph,'-map','[out]','-map','0:a:0']
        else: args+=['-vf',video]
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
    expression="if(lt(t,18),0.10,if(lt(t,44),0.20,if(lt(t,52.5),0.27,0.025)))"
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
