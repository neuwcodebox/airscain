"""Capture real Godot takes in an isolated project, then retain a compact master.

Usage: python tools/trailer/produce.py capture intro --lang ko --seconds 12
All media is under build/trailer_v3, never in the game's distributable resources.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build' / 'trailer_v3'
FFMPEG = shutil.which('ffmpeg') or r'D:\Utils\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe'
GODOT = shutil.which('godot')


def prepare() -> Path:
    for name in ['project', 'raw', 'review', 'assets', 'takes', 'logs', 'user-data']:
        (OUT / name).mkdir(parents=True, exist_ok=True)
    (ROOT / 'build' / '.gdignore').write_text('')
    stage = OUT / 'project'
    for source in ROOT.iterdir():
        if not source.is_dir() or source.name in ['.git', '.agents', '.codex', '%SystemDrive%']:
            continue
        link = stage / source.name
        if not link.exists():
            quote = lambda p: "'" + str(p).replace("'", "''") + "'"
            subprocess.run(['powershell', '-NoProfile', '-Command',
                f'New-Item -ItemType Junction -Path {quote(link)} -Target {quote(source)} | Out-Null'], check=True)
    project = (ROOT / 'project.godot').read_text(encoding='utf-8')
    for old, new in [('viewport_width=1600', 'viewport_width=1920'),
                     ('viewport_height=900', 'viewport_height=1080'),
                     ('window_width_override=1600', 'window_width_override=1920'),
                     ('window_height_override=900', 'window_height_override=1080')]:
        project = project.replace(old, new)
    (stage / 'project.godot').write_text(project, encoding='utf-8')
    return stage


def capture(shot: str, language: str, seconds: float) -> None:
    stage = prepare()
    name = f'{shot}_{language}'
    raw = OUT / 'raw' / f'{name}.avi'
    log = OUT / 'logs' / f'{name}.log'
    env = os.environ.copy()
    env['APPDATA'] = str(OUT / 'user-data')
    args = [GODOT, '--audio-driver', 'Dummy', '--path', str(stage),
            '--script', 'res://tools/trailer/capture.gd', '--fixed-fps', '60',
            '--disable-vsync', '--write-movie', str(raw), '--',
            f'--shot={shot}', f'--lang={language}', f'--seconds={seconds}']
    print(f'CAPTURE {name} {seconds}s', flush=True)
    with log.open('w', encoding='utf-8') as f:
        result = subprocess.run(args, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT)
    transcript = log.read_text(encoding='utf-8')
    # The isolated Windows account cannot read its CA store; this is unrelated
    # to offline rendering. All script, runtime and fixture errors are failures.
    errors = [line for line in transcript.splitlines()
              if ('ERROR:' in line or 'SCRIPT ERROR:' in line)
              and 'root certificate store' not in line]
    if result.returncode or errors or f'TRAILER_DONE shot={shot}' not in transcript:
        raise RuntimeError(f'{name}: capture failed: {errors}; see {log}')
    report = json.loads((OUT / 'review' / f'{name}.json').read_text(encoding='utf-8'))
    start = report['first_movie_frame'] / 60.0
    target = OUT / 'takes' / f'{name}.mkv'
    command = [FFMPEG, '-y', '-v', 'error', '-ss', str(start), '-i', str(raw),
               '-t', str(seconds), '-c:v', 'libx264', '-preset', 'fast', '-crf', '15',
               '-pix_fmt', 'yuv420p', '-c:a', 'flac', str(target)]
    subprocess.run(command, check=True)
    print(f'DONE {name} kills={report["kills"]} peak={report["peak_threats"]} city={report["city_integrity"]}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['capture'])
    parser.add_argument('shots', nargs='+', choices=['intro', 'raid'])
    parser.add_argument('--lang', default='ko', choices=['ko', 'en'])
    parser.add_argument('--seconds', type=float, default=12)
    options = parser.parse_args()
    for selected in options.shots:
        capture(selected, options.lang, options.seconds)
