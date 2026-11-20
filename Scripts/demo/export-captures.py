#!/usr/bin/env python3
"""Export one native capture batch; reject missing, empty or truncated footage."""
import hashlib, json, os, pathlib, subprocess, sys

manifest, output, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
spec = json.loads(manifest.read_text())
raw = output / 'raw'
site = output / 'site'
site.mkdir(exist_ok=True)

def run(*args):
    subprocess.run(args, check=True)

def still(movie, at, dest):
    run('ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(at), '-i', str(movie), '-frames:v', '1', '-threads', '2', str(dest))
    run(sys.argv[4], '--verify-image', str(dest))

expected = [f"music-{i:02d}-{song['key']}" for i,song in enumerate(spec['songs'],1)]
if mode == 'test': expected = expected[:1] + ['music-terminal','tour','page-music-terminal','page-timers','tape']
elif mode != 'stills': expected += ['music-showcase','music-terminal']
extra = ['calendar-life','clock-match','page-homebrew','kemosabe-sarah','tape','reel']
if mode == 'videos': expected += ['tour'] + extra
# Stills runs record no video, so they never make (or replace) one.
if mode == 'all': expected += ['tour','themes','ascii']
if mode not in ('music','test','videos'): expected += ['page-music-tint','page-music-terminal','page-music-devices','page-theme-terminal','page-theme-terminal-light'] + ['page-'+x for x in ['home','music','calendar','timers','notes','prompter','coding','usage','shortcuts','tray','weather','clock','system','meetings','dictation','wisp-hello','wisp','ascii']]
if mode not in ('music','test','videos'): expected += ['page-'+x for x in ['stats','backups','backup-compare','shelf'] + ['folio-'+f for f in ['library','board','viewer','search','colors','links']]]
if mode == 'all': expected += extra
def encode_frames(name, movie):
    """A clip drawn frame by frame (`rendered` in WebsiteDemoClips) becomes its movie here, at the
    harness's fixed rate, with the 0.4 s lead the live recordings have, so it's exported the same way."""
    frames = raw / ('clip-' + name)
    if movie.is_file() or not (frames / 'f00000.png').is_file(): return
    fps = os.environ.get('MACSPACES_DEMO_FPS', '60')
    run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-framerate',fps,'-i',str(frames/'f%05d.png'),
        '-vf','tpad=start_duration=0.4:start_mode=clone','-an','-c:v','libx264','-threads','2','-preset','medium','-crf','10',
        '-pix_fmt','yuv420p','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709',str(movie))

for name in expected:
    movie = raw / (name + '.mov')
    encode_frames(name, movie)
    if not movie.is_file(): raise RuntimeError(f'Missing required capture: {name}')
    probe = json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,duration,nb_frames','-of','json',str(movie)]))['streams'][0]
    required = 7 if name == 'calendar-life' else 8 if name in ('clock-match','kemosabe-sarah') else 9.6 if name == 'tape' else 15 if name == 'reel' else 21.5 if name == 'tour' else 8.8 if name == 'themes' else 10 if name == 'ascii' else len(spec['songs']) * spec['segmentSeconds'] if name in ('music-showcase','music-terminal') else (3 if name.startswith('music-') else (3.5 if name == 'page-music' else 3))
    if (probe['width'],probe['height']) != (1640,940) or float(probe.get('duration',0)) < required + .25:
        raise RuntimeError(f'Bad size or truncated capture: {name}: {probe}')
    if name == 'music-showcase':
        run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-ss','0.4','-i',str(movie),'-t',str(required),'-an','-c:v','libx264','-threads','2','-preset','medium','-crf','19','-pix_fmt','yuv420p','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-movflags','+faststart',str(site/'music.mp4'))
    elif name == 'music-terminal':
        # The Terminal reel: its own video and a poster with the first lyric landed.
        run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-ss','0.4','-i',str(movie),'-t',str(required),'-an','-c:v','libx264','-threads','2','-preset','medium','-crf','22','-pix_fmt','yuv420p','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-movflags','+faststart',str(site/'music-terminal.mp4'))
        still(movie, 3.2, site/'music-terminal-poster.png')
    elif name in ('tour','themes','calendar-life','clock-match','kemosabe-sarah','tape','reel'):
        # The tour becomes the site's hero video; its poster is the player with the lyric landed.
        # The hero reel (`reel`, 15 s, drawn at 60 fps) is CRF 22; its poster is BRIGHT landed on Music.
        video = {'tour':'notch','themes':'themes'}.get(name,name)
        run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-ss','0.4','-i',str(movie),'-t',str(required),'-an','-c:v','libx264','-threads','2','-preset','medium','-crf','22' if name == 'reel' else '19','-pix_fmt','yuv420p','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-movflags','+faststart',str(site/(video+'.mp4')))
        # Tape's poster: the new window centred in the strip (WebsiteDemoTape.posterAt, after the 0.4 s pre-roll).
        still(movie, 5.2 if name == 'tour' else 3.7 if name == 'reel' else 1.2 if name == 'themes' else 4.0 if name == 'tape' else required - .5, site/(video+'-poster.png'))
    elif name == 'ascii':
        # The ASCII demo: its ten seconds as the site's video, and its first second as the poster.
        run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-ss','0.4','-i',str(movie),'-t','10','-an','-c:v','libx264','-threads','2','-preset','medium','-crf','19','-pix_fmt','yuv420p','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-movflags','+faststart',str(site/'ascii.mp4'))
        still(movie, 1.2, site/'ascii-poster.png')
    elif name.startswith('music-'):
        still(movie, 0.4 + spec["posterSeconds"], site/(name+'.png'))
    else:
        still(movie, .4 + min(required * .6, 2.5), site/(name+'.png'))
# Explicit poster, independent of transitions and the old page-music naming collision.
first = site / (expected[0] + '.png')
(site/'music-poster.png').write_bytes(first.read_bytes())
# Five frames in order at readable resolution; native screenshots themselves are preserved.
inputs=[]
for name in ([] if mode == 'test' else expected[:len(spec['songs'])]): inputs += ['-i',str(site/(name+'.png'))]
filter_parts=[f'[{i}:v]scale=656:376[v{i}]' for i in range(len(spec['songs']))]
filter_parts += [''.join(f'[v{i}]' for i in range(len(spec['songs'])))+'hstack=inputs=5[out]']
if mode != 'test': run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y',*inputs,'-filter_complex',';'.join(filter_parts),'-map','[out]','-frames:v','1','-threads','2',str(output/'music-proof.png'))
provenance={'capture':'ScreenCaptureKit isolated window; native effects; no audio or pointer; real-time animation', 'sequence':spec,
    'tracks':json.loads((output/'tracks-provenance.json').read_text()) if (output/'tracks-provenance.json').exists() else {},
    'assets':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(site.iterdir())}}
(output/'capture.json').write_text(json.dumps(provenance,indent=2)+'\n')
print(f'Validated {len(expected)} captures; see {output / "music-proof.png"}')
