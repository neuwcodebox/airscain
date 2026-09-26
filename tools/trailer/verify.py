"""Inspect delivery structure, decoded frames, timeline boundaries and audio.

Technical checks do not assert that a person listened to the final mix.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont
from produce import OUT, FFMPEG
from edit import TOTAL_SECONDS, ACTION_END, MUSIC_GAIN, TERMINAL_FRAME, FIRST_BLACK_FRAME

FFPROBE = str(Path(FFMPEG).with_name('ffprobe.exe'))


def continuity(language: str) -> dict:
    """Verify story requirements against actual runtime events and source ranges."""
    lang = 'en' if language == 'en' else 'ko'
    intro=json.loads((OUT/'review'/f'intro_{lang}.json').read_text(encoding='utf-8'))
    raid=json.loads((OUT/'review/raid_ko.json').read_text(encoding='utf-8'))
    expansion=json.loads((OUT/'review/expansion_ko.json').read_text(encoding='utf-8'))
    for take in (intro,raid,expansion):
        assert take['continuous_take']
        assert all(b['frame']<0 or (b['type']=='ballistic_missile' and b['outside_view']) for b in take['births'])
        original={a['id']:a for a in take['initial_assets']}
        final={a['id']:a for a in take['assets']}
        assert all(final.get(key)==value for key,value in original.items())
    assert intro['contact_audio_events']>0
    assert all(t['contact_audio_events']==0 for t in [raid,expansion])
    installs=[e for e in intro['events'] if e['event'] in ['radar_placed','asset_placed']]
    assert {e['asset'] for e in installs}=={'search_radar','missile_battery','close_in_gun'}
    first_fire=min(e['frame'] for e in intro['events'] if e['event']=='fire')
    last_placement=max(e['frame'] for e in installs)
    assert 0<first_fire-last_placement<180
    growth=[e['count'] for e in expansion['events'] if e['event']=='expansion']
    assert len(growth)==3 and growth[0]<growth[1]<growth[2]
    assert intro['assets']==expansion['initial_assets']
    assert expansion['assets']==raid['initial_assets']
    assert len(raid['births'])==101
    assert sum(b['frame']<0 for b in raid['births'])==100
    assert raid['scripted_spawns_during_capture']==1
    assert all(t['scripted_spawns_during_capture']==0 for t in [intro,expansion])
    hard_cuts={e['frame'] for e in raid['events'] if e['event']=='camera' and e.get('hard_cut')}
    for before,after in zip(raid['camera_frames'],raid['camera_frames'][1:]):
        if after['frame']<2340 and after['frame'] not in hard_cuts:
            assert math.dist(before['p'],after['p'])<4
            assert abs(before['fov']-after['fov'])<.15
    assert min(e['frame'] for e in raid['events'] if e['event']=='fire')>=840

    phases=[e for e in raid['events'] if e['event']=='ballistic_phase']
    reentry=next(e['frame'] for e in phases if e['phase']=='reentry')
    assert abs(reentry-2340)<=40, 'First missile cut must coincide with reentry onset'
    resolution=min(e['frame'] for e in raid['events'] if e.get('threat')=='ballistic_missile')
    assert 0 < resolution-TERMINAL_FRAME <= 6
    assert raid['city_integrity']>0
    tracked=[c for c in raid['camera_frames'] if 2340<=c['frame']<=TERMINAL_FRAME]
    assert all('missile_screen' in c for c in tracked)
    assert all(.05<c['missile_screen'][0]<.95 and .05<c['missile_screen'][1]<.95 for c in tracked)
    assert math.dist(expansion['camera_frames'][0]['p'],expansion['camera_frames'][-1]['p'])>400
    assert math.dist(expansion['camera_frames'][-1]['p'],raid['camera_frames'][360]['p'])<.02
    assert all(c['time_scale']==1 for c in raid['camera_frames'][:2490])
    assert all(c['time_scale']==.5 for c in raid['camera_frames'][2490:])
    assert 0<raid['camera_frames'][TERMINAL_FRAME]['missile_clearance']<40
    assert raid['camera_frames'][FIRST_BLACK_FRAME]['missile_clearance']<80
    terminal=raid['camera_frames'][FIRST_BLACK_FRAME:TERMINAL_FRAME+1]
    assert all('interceptor_screen' in c for c in terminal)
    assert all(.02<c['interceptor_screen'][0]<.98 and .02<c['interceptor_screen'][1]<.98 for c in terminal)
    assert all(c['interceptor_visible'] for c in terminal), 'Terminal interceptor must not be hidden by city buildings'
    assert MUSIC_GAIN=='0.09' and not (OUT/'assets/siren.wav').exists()
    timeline=json.loads((OUT/'edit'/language/'timeline.json').read_text())
    holds=[r for r in timeline if r['hold']]
    first_dark=next(r for r in timeline if r['dark'])
    assert all(not r['hold'] for r in timeline if r['timeline_start']<first_dark['timeline_start'])
    assert len(holds)==14 and holds[0]['dark']==1
    for row in timeline:
        if row['shot']=='raid': assert round(row['start']*60)+row['source_frames']<=resolution
        if row['shot']=='raid' and not row['hold']:
            assert row['speed']==(2 if row['start']>=41.5 else 1)
    assert sum(r['frames'] for r in timeline)==round(TOTAL_SECONDS*60)
    assert not any(r['caption'] in ['warning','build','expand'] for r in timeline)
    return {'contact_audio_intro':intro['contact_audio_events'],'contact_audio_after_intro':0,
            'expansion_asset_counts':growth,'preexisting_raid_aircraft':100,'same_raid_ballistic_missiles':1,'reentry_source_second':reentry/60,
            'last_placement_to_first_fire_seconds':(first_fire-last_placement)/60,
            'ballistic_reentry_observed':True,'ballistic_resolution_shown':False,
            'expansion_camera_tracks_ground':True,'sea_reveal_join_position_error':math.dist(expansion['camera_frames'][-1]['p'],raid['camera_frames'][360]['p']),
            'terminal_clearance_m':raid['camera_frames'][TERMINAL_FRAME]['missile_clearance'],'first_black_source_frame':FIRST_BLACK_FRAME,'last_visible_source_frame':TERMINAL_FRAME,
            'result':'pass'}


def inspect(path: Path,language: str) -> None:
    folder=OUT/'qa'/language;folder.mkdir(parents=True,exist_ok=True)
    story=continuity(language)
    info=json.loads(subprocess.check_output([FFPROBE,'-v','error','-count_frames',
        '-show_streams','-show_format','-of','json',str(path)],text=True))
    video=next(s for s in info['streams'] if s['codec_type']=='video')
    audio=next(s for s in info['streams'] if s['codec_type']=='audio')
    assert (video['width'],video['height'])==(1920,1080)
    assert video['codec_name']=='h264' and video['r_frame_rate']=='60/1'
    assert audio['codec_name']=='aac' and audio['channels']==2
    assert int(video['nb_read_frames'])==round(TOTAL_SECONDS*60),video['nb_read_frames']
    assert abs(float(info['format']['duration'])-TOTAL_SECONDS)<0.06,info['format']['duration']
    scan=subprocess.run([FFMPEG,'-hide_banner','-i',str(path),'-vf',
        'blackdetect=d=0.05:pix_th=0.04,freezedetect=n=-55dB:d=1',
        '-af','ebur128=peak=true','-f','null','NUL'],capture_output=True,text=True,check=True)
    (folder/'decode-audio-scan.log').write_text(scan.stderr,encoding='utf-8')
    loud=subprocess.run([FFMPEG,'-hide_banner','-i',str(path),'-af',
        'loudnorm=I=-16:TP=-1.5:LRA=9:print_format=json','-vn','-f','null','NUL'],
        capture_output=True,text=True,check=True)
    block=loud.stderr[loud.stderr.rfind('{'):loud.stderr.rfind('}')+1]
    measurements=json.loads(block)
    assert float(measurements['input_tp'])<=-0.8,measurements
    assert -25<float(measurements['input_i'])<-14,measurements
    gain=json.loads((OUT/'edit'/language/'static-gain.json').read_text())
    assert gain['dynamic_normalization'] is False
    anomalies=[line for line in scan.stderr.splitlines()
               if 'black_start:' in line or 'freeze_start:' in line]
    black_starts=[float(line.split('black_start:')[1].split()[0]) for line in anomalies if 'black_start:' in line]
    assert all(16.8<=t<=21.2 or ACTION_END-4<=t for t in black_starts),anomalies
    freeze_starts=[float(line.rsplit(':',1)[1]) for line in anomalies if 'freeze_start:' in line]
    assert all(t>=ACTION_END-4 for t in freeze_starts),anomalies
    # Distant aircraft occupy few pixels against a stationary sea/sky. The global
    # noise threshold flags these shots although every decoded frame changes.
    # Confirm the entire four-second range, plus actual per-aircraft movement.
    approach_hashes=subprocess.check_output([FFMPEG,'-v','error','-ss','23','-i',str(path),
        '-t','4','-an','-f','framemd5','-'],text=True)
    (folder/'approach-frame-hashes.txt').write_text(approach_hashes)
    approach_frames=[line.rsplit(',',1)[1].strip() for line in approach_hashes.splitlines()
                     if line and not line.startswith('#')]
    assert len(approach_frames)==240 and len(set(approach_frames))==240
    raid=json.loads((OUT/'review'/'raid_ko.json').read_text(encoding='utf-8'))
    aircraft_ids={b['id'] for b in raid['births'] if b['frame']<0}
    for before,after in zip(raid['samples'][6:10],raid['samples'][7:11]):
        positions={t['id']:t['p'] for t in after['threats'] if t['id'] in aircraft_ids}
        assert set(positions)==aircraft_ids
        assert all(t['p']!=positions[t['id']] for t in before['threats'] if t['id'] in aircraft_ids)
    timeline=json.loads((OUT/'edit'/language/'timeline.json').read_text())
    black_counts=[]
    for row in [r for r in timeline if r['dark']]:
        second=row['timeline_start']/60
        pixels=subprocess.check_output([FFMPEG,'-v','error','-ss',str(second),'-i',str(path),
            '-frames:v',str(row['frames']),'-vf','scale=32:18,format=rgb24','-an','-f','rawvideo','-'])
        assert len(pixels)==row['frames']*32*18*3 and max(pixels)==0
        black_counts.append(row['frames'])
    assert len(black_counts)==7 and all(a>b for a,b in zip(black_counts,black_counts[1:]))
    for row in [r for r in timeline if r['hold'] and not r['dark']]:
        pixels=subprocess.check_output([FFMPEG,'-v','error','-ss',str(row['timeline_start']/60),'-i',str(path),
            '-frames:v',str(row['frames']),'-vf','scale=32:18,format=rgb24','-an','-f','rawvideo','-'])
        size=32*18*3
        frames=[pixels[i:i+size] for i in range(0,len(pixels),size)]
        assert len(frames)==row['frames']
        # H.264 may quantize repeated frames differently; the scene must stay still.
        assert max(sum(abs(a-b) for a,b in zip(frames[0],f))/size for f in frames)<1.5

    report={'container':info,'audio':measurements,'story_continuity':story,
            'full_black_cut_frames':black_counts,
            'perceptual_audio_review':'not independently heard; objective inspection only',
            'visual_review':'contact sheets and moving-frame samples require inspection',
            'black_or_freeze_events':anomalies,
            'approach_motion':'240/240 distinct decoded frames; all 100 fleet threats move in each one-second interval',
            'ending':'normal descent until first blackout; seven advancing still moments; paired interceptor; no outcome'}
    (folder/'technical-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    timeline=json.loads((OUT/'edit'/language/'timeline.json').read_text())
    images=[]
    for i,row in enumerate(timeline):
        second=(row['timeline_start']+row['frames']/2)/60
        png=folder/f'{i:02d}.jpg'
        subprocess.run([FFMPEG,'-y','-v','error','-ss',str(second),'-i',str(path),
            '-frames:v','1','-vf','scale=640:360','-q:v','2',str(png)],check=True)
        images.append((png,f'{second:05.2f}s  {row["shot"]}'))
    for page in range((len(images)+11)//12):
        sheet=Image.new('RGB',(1920,4*400),(12,19,24));d=ImageDraw.Draw(sheet)
        for n,(png,label) in enumerate(images[page*12:page*12+12]):
            x=n%3*640;y=n//3*400
            sheet.paste(Image.open(png),(x,y));d.text((x+12,y+369),label,fill=(230,240,244))
        sheet.save(folder/f'contact-{page+1}.jpg',quality=94)
    print(f'PASS {language}: 1920x1080, {round(TOTAL_SECONDS*60)} frames, stereo AAC; I={measurements["input_i"]} LUFS, TP={measurements["input_tp"]} dBTP')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--lang',choices=['ko','en','ko_clean'],default='ko')
    opt=parser.parse_args();inspect(OUT/f'Airscain_Launch_Trailer_{opt.lang.upper()}.mp4',opt.lang)
