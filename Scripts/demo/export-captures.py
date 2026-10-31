#!/usr/bin/env python3
"""Export one native capture batch; reject missing, empty or truncated footage."""
import hashlib, json, pathlib, subprocess, sys

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
if mode != 'stills': expected += ['music-showcase']
if mode != 'music': expected += ['page-'+x for x in ['home','music','calendar','timers','notes','prompter','coding','usage','shortcuts','tray','weather','clock','system','meetings','dictation','wisp-hello','wisp','ascii']] + ['ascii']
for name in expected:
    movie = raw / (name + '.mov')
    if not movie.is_file(): raise RuntimeError(f'Missing required capture: {name}')
    probe = json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,duration,nb_frames','-of','json',str(movie)]))['streams'][0]
    required = 10 if name == 'ascii' else len(spec['songs']) * spec['segmentSeconds'] if name == 'music-showcase' else (3 if name.startswith('music-') else (3.5 if name == 'page-music' else 3))
    if (probe['width'],probe['height']) != (1640,940) or float(probe.get('duration',0)) < required + .25:
        raise RuntimeError(f'Bad size or truncated capture: {name}: {probe}')
    if name == 'music-showcase':
        run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-ss','0.4','-i',str(movie),'-t',str(required),'-an','-c:v','libx264','-threads','2','-preset','medium','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(site/'music.mp4'))
    elif name == 'ascii':
        # The ASCII demo: its ten seconds as the site's video, and its first second as the poster.
        run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y','-ss','0.4','-i',str(movie),'-t','10','-an','-c:v','libx264','-threads','2','-preset','medium','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(site/'ascii.mp4'))
        still(movie, 1.2, site/'ascii-poster.png')
    elif name.startswith('music-'):
        still(movie, 0.4 + spec["posterSeconds"], site/(name+'.png'))
        if name == expected[0]:
            run(sys.argv[4], '--verify-star', str(site/(name+'.png')))
    else:
        still(movie, .4 + min(required * .6, 2.5), site/(name+'.png'))
# Explicit poster, independent of transitions and the old page-music naming collision.
first = site / (expected[0] + '.png')
(site/'music-poster.png').write_bytes(first.read_bytes())
# Five frames in order at readable resolution; native screenshots themselves are preserved.
inputs=[]
for name in expected[:len(spec['songs'])]: inputs += ['-i',str(site/(name+'.png'))]
filter_parts=[f'[{i}:v]scale=656:376[v{i}]' for i in range(len(spec['songs']))]
filter_parts += [''.join(f'[v{i}]' for i in range(len(spec['songs'])))+'hstack=inputs=5[out]']
run('ffmpeg','-nostdin','-hide_banner','-loglevel','error','-y',*inputs,'-filter_complex',';'.join(filter_parts),'-map','[out]','-frames:v','1','-threads','2',str(output/'music-proof.png'))
provenance={'capture':'ScreenCaptureKit isolated window; native effects; no audio or pointer; real-time animation', 'sequence':spec,
    'tracks':json.loads((output/'tracks-provenance.json').read_text()) if (output/'tracks-provenance.json').exists() else {},
    'assets':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(site.iterdir())}}
(output/'capture.json').write_text(json.dumps(provenance,indent=2)+'\n')
print(f'Validated {len(expected)} captures; see {output / "music-proof.png"}')
