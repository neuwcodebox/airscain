"""Frame-based editorial conform, caption artwork and loudness-controlled mix.

No rendered frame fabricates game UI, projectiles, impacts or weapon effects.
Only typography, fades, brief editorial dips and dark ending cards are added.
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


def terminal_frame() -> int:
    report=OUT/'review/raid_ko.json'
    data=json.loads(report.read_text(encoding='utf-8'))
    resolution=min(e['frame'] for e in data['events'] if e.get('threat')=='ballistic_missile')
    # End within a few samples of impact, while both missile bodies still clear
    # the buildings. In-frustum coordinates alone do not prove visibility.
    return max(c['frame'] for c in data['camera_frames']
               if resolution-6<=c['frame']<resolution and c.get('interceptor_visible'))

BLINKS=[(9,60),(8,45),(7,32),(6,23),(5,16),(4,10),(3,6)]
TERMINAL_FRAME=terminal_frame()
FIRST_BLACK_FRAME=TERMINAL_FRAME-7
NORMAL_TERMINAL_FRAMES=round((FIRST_BLACK_FRAME-2490)/2)
ACTION_FRAMES=17*60+6*60+round((41.5-6)*60)+NORMAL_TERMINAL_FRAMES+sum(a+b for a,b in BLINKS)
ACTION_END=ACTION_FRAMES/60
TOTAL_SECONDS=(ACTION_FRAMES+456)/60
MUSIC_GAIN = "0.09"


def run(args: list[str]) -> None:
    subprocess.run([FFMPEG, '-y', '-hide_banner', '-loglevel', 'error', *args], check=True)


def art(language: str) -> dict[str, Path]:
    folder = OUT / 'graphics'
    folder.mkdir(exist_ok=True)
    words = {'call': '당신의 지휘를 기다립니다.' if language == 'ko' else 'AWAITING YOUR COMMAND.'}
    files = {}
    for key, title in words.items():
        image = Image.new('RGBA', (1920,1080))
        draw = ImageDraw.Draw(image)
        font = ImageFont.truetype(str(FONT if language=='ko' else LATIN),62)
        width=draw.textbbox((0,0),title,font=font)[2]
        draw.text(((1920-width)/2,491),title,font=font,fill=(245,248,249))
        target=folder/f'{key}_{language}.png'
        image.save(target);files[key]=target
    image=Image.new('RGBA',(1920,1080));draw=ImageDraw.Draw(image)
    def centered(text: str,y: int,font: ImageFont.FreeTypeFont,color: tuple):
        width=draw.textbbox((0,0),text,font=font)[2]
        draw.text(((1920-width)/2,y),text,font=font,fill=color)
    centered('실시간 방공 전략' if language=='ko' else 'AIR DEFENSE / REAL-TIME STRATEGY',358,ImageFont.truetype(str(FONT if language=='ko' else LATIN),25),(157,188,199))
    centered('AIRSCAIN',412,ImageFont.truetype(str(LATIN),142),(244,247,248))
    draw.rectangle((909,597,1011,600),fill=(255,181,70))
    centered('지금 플레이하세요' if language=='ko' else 'PLAY NOW',640,
             ImageFont.truetype(str(FONT if language=='ko' else LATIN),43),(255,192,94))
    centered('Music: Volatile Reaction — Kevin MacLeod (incompetech.com) · CC BY 4.0 · Edited',1000,
             ImageFont.truetype(str(FONT),21),(177,190,196))
    target=folder/f'end_{language}.png';image.save(target);files['end']=target
    return files


def timeline(language: str) -> list[dict]:
    def row(shot,start,end,caption=None,dark=0,speed=1,hold=0):
        source_frames=round((end-start)*60)
        return dict(shot=shot,lang=language if shot=='intro' else 'ko',start=start,
                    frames=hold or round(source_frames/speed),source_frames=source_frames,
                    caption=caption,dark=dark,dip=False,speed=speed,hold=bool(hold))
    rows=[row('intro',0,5),row('intro',5,7),row('intro',7,9),row('intro',9,11),row('intro',11,15),row('intro',15,17)]
    rows += [row('expansion',t,t+2) for t in [0,2,4]]
    cuts=[6,14,20.5,27,33.5,39,41.5]
    rows += [row('raid',a,b) for a,b in zip(cuts,cuts[1:])]
    # Terminal source is sampled at half simulation time; restore normal speed
    # before the first blackout. Only after blackout are still moments held.
    rows.append(row('raid',41.5,FIRST_BLACK_FRAME/60,speed=2))
    for i,(black,lit) in enumerate(BLINKS):
        source=FIRST_BLACK_FRAME+i
        rows.append(row('raid',source/60,(source+1)/60,dark=1,hold=black))
        rows.append(row('raid',(source+1)/60,(source+2)/60,hold=lit))
    rows += [row('outro',0,.6),row('outro',.6,2.6,'call'),row('outro',2.6,7.6,'end')]
    assert sum(r['frames'] for r in rows)==round(TOTAL_SECONDS*60)
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
    black=OUT/'takes/outro_ko.mkv'
    if not black.exists():
        run(['-f','lavfi','-i','color=c=0x02070c:s=1920x1080:r=60:d=7.6','-f','lavfi','-i',
             'anullsrc=r=48000:cl=stereo','-t','7.6','-c:v','libx264','-pix_fmt','yuv420p',
             '-c:a','pcm_s24le',str(black)])
    segments=[]
    for i,r in enumerate(rows):
        target=work/f'{i:02d}.mkv';segments.append(target)
        source=OUT/'takes'/f'{r["shot"]}_{r["lang"]}.mkv'
        if not source.exists(): raise FileNotFoundError(source)
        probe=str(Path(FFMPEG).with_name('ffprobe.exe'))
        source_length=float(subprocess.check_output([probe,'-v','error','-show_entries',
            'format=duration','-of','default=noprint_wrappers=1:nokey=1',str(source)],text=True))
        if r['start']+r['source_frames']/60>source_length+0.02:
            raise ValueError(f'Source take too short for edit: {source.name}')
        signature=hashlib.sha256(json.dumps(r,sort_keys=True).encode()+
            str(source.stat().st_mtime_ns).encode()+Path(__file__).read_bytes()+
            (graphics[r['caption']].read_bytes() if r['caption'] and not no_text else b'')).hexdigest()
        stamp=target.with_suffix('.sha256')
        if target.exists() and stamp.exists() and stamp.read_text()==signature: continue
        duration=r['frames']/60
        args=['-ss',str(r['start']),'-i',str(source)]
        filters=[f'setpts=(PTS-STARTPTS)/{r["speed"]}','fps=60','setsar=1','scale=in_range=auto:out_range=tv','format=yuv420p','setparams=range=limited']
        if r['hold']: filters += ['trim=end_frame=1','setpts=PTS-STARTPTS',f'tpad=stop_mode=clone:stop_duration={duration}']
        if r['dark']:filters.append(f'drawbox=c=black@{r["dark"]}:t=fill')
        if r['shot']=='intro' and r['start']==15: filters.append(f'fade=t=out:st={duration-.14}:d=0.14')
        if r['shot']=='expansion':
            filters.append('fade=t=in:d=0.14')
            if r['start']<4: filters.append(f'fade=t=out:st={duration-.14}:d=0.14')
        if r['dip']:filters.append(f'fade=t=out:st={duration-2/60}:d={2/60}')
        video=','.join(filters)
        graph=[f'[0:v]{video}[v]'];base='v';input_index=1
        if r['caption'] and not no_text:
            args+=['-loop','1','-i',str(graphics[r['caption']])]
            graph += [f'[{input_index}:v]format=rgba,fade=t=in:d=0.18:alpha=1,fade=t=out:st={duration-.18}:d=0.18:alpha=1[title]',
                      f'[{base}][title]overlay=0:0:shortest=1[out]']
            base='out'
        args+=['-filter_complex',';'.join(graph),'-map',f'[{base}]','-map','0:a:0']
        args+=['-t',str(duration),'-frames:v',str(r['frames']),'-c:v','libx264','-preset','fast',
               '-crf','16','-pix_fmt','yuv420p','-af',('volume=0,apad' if r['hold'] else f'atempo={r["speed"]},afade=t=in:d=0.012,afade=t=out:st={max(0,duration-.03)}:d=0.03'),
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
    # Constant music gain throughout the battle; only opening/ending fades.
    graph=f"[0:a]volume=0.70,afade=t=out:st={ACTION_END-.15}:d=0.15[sfx];[1:a]atrim=0:{TOTAL_SECONDS},asetpts=PTS-STARTPTS,volume={MUSIC_GAIN},afade=t=in:d=0.25,afade=t=out:st={ACTION_END-.15}:d=0.15[m];[sfx][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.90:level=0[out]"
    run(['-i',str(assembled),'-i',str(OUT/'assets/volatile-reaction.mp3'),'-filter_complex',graph,'-map','[out]','-t',str(TOTAL_SECONDS),'-ar','48000','-c:a','pcm_s24le',str(mix)])
    # Measure the mix, then choose one fixed gain for the entire master.
    measure=subprocess.run([FFMPEG,'-hide_banner','-i',str(mix),'-af','loudnorm=I=-16:TP=-1.5:LRA=9:print_format=json','-f','null','NUL'],capture_output=True,text=True,check=True)
    block=measure.stderr[measure.stderr.rfind('{'):measure.stderr.rfind('}')+1]
    metrics=json.loads(block)
    (work/'loudness-input.json').write_text(json.dumps(metrics,indent=2))
    # A single static gain preserves the music envelope. Dynamic normalization
    # used in older versions could raise the background between combat transients.
    gain_db=min(-16.0-float(metrics['input_i']),-1.5-float(metrics['input_tp']))
    norm=f'volume={gain_db}dB'
    (work/'static-gain.json').write_text(json.dumps({'gain_db':gain_db,'peak_ceiling_db':-1.5,'dynamic_normalization':False},indent=2))

    final=OUT/f'Airscain_Launch_Trailer_{label.upper()}.mp4'
    run(['-i',str(assembled),'-i',str(mix),'-map','0:v:0','-map','1:a:0','-c:v','copy','-af',norm,'-ar','48000','-c:a','aac','-b:a','320k','-t',str(TOTAL_SECONDS),'-movflags','+faststart',str(final)])
    print(f'MASTER {final}',flush=True)
    return final


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--lang',choices=['ko','en'],default='ko');p.add_argument('--clean',action='store_true')
    options=p.parse_args();render(options.lang,options.clean)
