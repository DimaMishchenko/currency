from pathlib import Path
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont, ImageChops, features
import argparse, hashlib, html, json, math, os, shutil, subprocess, sys, xml.etree.ElementTree as ET
from generate import DESIGN, load, verified_object
from header_validation import background_identity, pixel_source_sha256, validate_entry

parser = argparse.ArgumentParser(description='Render the fifteen second H09 currency header from frozen design geometry.')
parser.add_argument('--inputs', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--video', action='store_true')
parser.add_argument('--locale', action='append', choices=list(load(DESIGN / 'header-locales.json')['locales']))
parser.add_argument('--all-locales', action='store_true')
parser.add_argument('--gallery-only', action='store_true', help='Rebuild the gallery from completed selected locale manifests.')
parser.add_argument('--render-locale', choices=list(load(DESIGN / 'header-locales.json')['locales']), help=argparse.SUPPRESS)
args = parser.parse_args()
configuration = load(DESIGN / 'header-locales.json')
SOURCE = DESIGN / 'header.svg'
FONT = verified_object(args.inputs, 'bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207', load(DESIGN / 'input-manifest.json')['objects'])
renderer_source = Path(__file__).read_text()
render_identity = {'pixelSourceSha256': pixel_source_sha256(renderer_source), 'sourceSha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'fontSha256': hashlib.sha256(FONT.read_bytes()).hexdigest(), 'configSha256': hashlib.sha256((DESIGN / 'header-locales.json').read_bytes()).hexdigest(), 'pillow': Image.__version__, 'freetype': features.version('freetype2')}

selected = list(configuration['locales']) if args.all_locales else args.locale
if selected:
    entries = []
    for locale in dict.fromkeys(selected):
        command = [sys.executable, __file__, '--inputs', str(args.inputs), '--output', str(args.output / locale), '--render-locale', locale]
        if args.video:
            command.append('--video')
        if not args.gallery_only:
            subprocess.run(command, check=True)
        entry = validate_entry(args.output, locale, configuration['locales'][locale], render_identity, args.video)
        entries.append(entry)
    cards = []
    for entry in entries:
        locale = entry['locale']
        label = html.escape(locale + ' · ' + ' / '.join(entry['currencies']))
        media = f'<video controls loop muted playsinline preload="none" poster="{locale}/poster.png" src="{locale}/header.mp4"></video>' if args.video else f'<img src="{locale}/poster.png" alt="{label}">'
        cards.append(f'<article><h2>{label}</h2>{media}<p>Center glyphs {html.escape(" / ".join(entry["glyphs"]))} · <a href="{locale}/manifest.json">Render proof</a></p></article>')
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'index.html').write_text('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Localized H09 review</title><style>body{font:16px system-ui;background:#eef3fc;color:#172034;margin:32px auto;max-width:1400px;padding:0 20px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(430px,1fr));gap:24px}article{background:white;padding:18px;border-radius:20px}h2{font-size:20px}video,img{width:100%;border-radius:12px}a{color:#075fcf}@media(max-width:500px){main{display:block}article{margin-bottom:20px}}</style><h1>H09 · language editions</h1><p>15 seconds · 60 fps · early upward reel spins · continuous leftward rails. Currency priorities follow the approved language examples. Review only.</p><main>' + ''.join(cards) + '</main>')
    (args.output / 'manifest.json').write_text(json.dumps({'schemaVersion': 1, 'status': 'local-review', 'headers': entries}, indent=2, ensure_ascii=False) + '\n')
    if args.video:
        (args.output / 'header-map.json').write_text(json.dumps({'schemaVersion': 1, 'headers': {entry['locale']: {'path': entry['locale'] + '/header.mp4', 'sha256': entry['videoSha256']} for entry in entries}}, indent=2, ensure_ascii=False) + '\n')
    raise SystemExit(0)
locale = args.render_locale
currencies = configuration['locales'][locale] if locale else None
W,H,FPS,DURATION=3840,1646,60,15
N=FPS*DURATION
SPACING,MARGIN,BAND=310,310,150
PERIOD=3*SPACING
SPEED=PERIOD/DURATION
NS='{http://www.w3.org/2000/svg}'
ET.register_namespace('',NS[1:-1])
FFMPEG=shutil.which('ffmpeg')
children=list(ET.parse(SOURCE).getroot())
rows=[children[2+i*16:2+(i+1)*16] for i in range(6)]
sequence=[x.text for x in rows[0][1:15]]
GROUP_STARTS=[0,2,4,7,9,11]
GROUPS=[[sequence[(start+j)%14] for j in range(3)] for start in GROUP_STARTS]
assert set(sum(GROUPS,[]))==set(sequence) and len(set(sequence))==14
REELS=[['€','₹','¥','$','₽','£','€'],['¥','€','₹','£','$','₩','¥'],['₹','£','€','₩','¥','$','₹']]
if currencies:
    glyphs = [configuration['glyphs'][code] for code in currencies]
    REELS = [[glyphs[i], glyphs[(i+1)%3], glyphs[(i+2)%3], glyphs[(i+1)%3], glyphs[(i+2)%3], glyphs[i], glyphs[i]] for i in range(3)]
SESSION_STARTS=[1.5,8.5]
SESSION_DURATION=1.6
STAGGER=0.12
PITCH=240

@lru_cache(maxsize=128)
def sprite(sign,size,color):
    f=ImageFont.truetype(str(FONT),size*2);f.set_variation_by_axes([900])
    b=f.getbbox(sign)
    im=Image.new('RGBA',(b[2]-b[0]+12,b[3]-b[1]+12))
    ImageDraw.Draw(im).text((6-b[0],6-b[1]),sign,font=f,fill=color)
    scale = min(0.5, 284 / im.width, 270 / im.height) if size == 178 else 0.5
    return im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.LANCZOS)

def center_paste(im,spr,x,y):
    im.alpha_composite(spr,(round(x-spr.width/2),round(y-spr.height/2)))

background=Image.new('RGB',(W,H));draw=ImageDraw.Draw(background)
for y in range(H):
    t=y/H;color=tuple(int(a*(1-t)+b*t) for a,b in zip((248,250,255),(220,234,255)))
    draw.line((0,y,W,y),fill=color)

strips=[]
for r,row in enumerate(rows):
    strip=Image.new('RGBA',(W+PERIOD+2*MARGIN,BAND))
    stagger=float(row[1].get('x'))
    for col in range(-1,math.ceil(strip.width/SPACING)+1):
        center_paste(strip,sprite(GROUPS[r][col%3],100,'#acc4e5'),MARGIN+col*SPACING+stagger,BAND/2)
    strips.append(strip.convert('RGBa'))

white_tile=Image.new('RGBA',(672,724))
ImageDraw.Draw(white_tile).rounded_rectangle((4,4,668,720),radius=140,fill='#ffffff')
white_tile=white_tile.resize((336,362),Image.Resampling.LANCZOS)
reel_mask=Image.new('L',(336,362))
mask_draw=ImageDraw.Draw(reel_mask)
for y in range(26,337):
    alpha=round(255*min(1,(y-26)/16,(336-y)/16))
    mask_draw.line((26,y,310,y),fill=max(0,alpha))
reel_mask=ImageChops.multiply(reel_mask,white_tile.getchannel('A'))
focal=[]
for i in range(3):
    rect=children[-6+i*2]
    reel=Image.new('RGBA',(336,362+6*PITCH))
    for j,sign in enumerate(REELS[i]):
        center_paste(reel,sprite(sign,178,'#1673ff'),168,181+j*PITCH)
    focal.append((reel.convert('RGBa'),round(float(rect.get('x')))-2,round(float(rect.get('y')))-2))


def smoothstep5(u):
    u=max(0,min(1,u))
    return u*u*u*(u*(u*6-15)+10)

def reel_position(t,index):
    return sum(3*smoothstep5((t-start-index*STAGGER)/SESSION_DURATION) for start in SESSION_STARTS)

@lru_cache(maxsize=16)
def settled_tile(index,position):
    return render_tile(index,position)

def render_tile(index,position):
    reel=focal[index][0]
    glyphs=reel.transform((336,362),Image.Transform.AFFINE,(1,0,0,0,1,position*PITCH),resample=Image.Resampling.BICUBIC).convert('RGBA')
    glyphs.putalpha(ImageChops.multiply(glyphs.getchannel('A'),reel_mask))
    tile=white_tile.copy();tile.alpha_composite(glyphs)
    return tile

def offset(frame):
    return PERIOD*(frame%N)/N

cache_identity = background_identity(render_identity)
background_cache = args.output.parent / '.header-backgrounds' / cache_identity if locale else None

def frame_image(frame):
    return image_at_offset(offset(frame),(frame%N)/FPS,frame%N)


def image_at_offset(scroll_offset,t=0,cache_index=None):
    cache_path = background_cache / f'{cache_index:04d}.png' if background_cache and cache_index is not None else None
    if cache_path and cache_path.exists():
        with Image.open(cache_path) as cached:
            assert cached.size == (W,H) and cached.mode == 'RGB'
            im = cached.copy()
    else:
        im=background.copy()
        for row,strip in zip(rows,strips):
            band=strip.transform((W,BAND),Image.Transform.AFFINE,(1,0,MARGIN+scroll_offset,0,1,0),resample=Image.Resampling.BICUBIC).convert('RGBA')
            y=round(float(row[0].get('y'))-BAND/2)
            im.paste(band,(0,y),band)
        if cache_path:
            cache_path.parent.mkdir(parents=True,exist_ok=True)
            temporary = cache_path.with_suffix(f'.{os.getpid()}.tmp')
            im.save(temporary,format='PNG',compress_level=1)
            temporary.replace(cache_path)
    for i,(reel,x,y) in enumerate(focal):
        position=reel_position(t,i)
        tile=settled_tile(i,int(position)) if position in (0,3,6) else render_tile(i,position)
        im.paste(tile,(x,y),tile)
    return im

args.output.mkdir(parents=True, exist_ok=True)
frame_image(0).resize((1280,549),Image.Resampling.LANCZOS).save(args.output/'poster.png')
sample_indices = [0, 1, 102, 109, 116, 138, 210, 450, 558, 630, 898, 899, 900]
samples = {str(index): hashlib.sha256(frame_image(index).tobytes()).hexdigest() for index in sample_indices}
assert samples['0'] == samples['900']
assert image_at_offset(0,0).tobytes() == image_at_offset(PERIOD,DURATION).tobytes()
for i in range(3):
    assert ImageChops.difference(render_tile(i,0).convert('RGB'),render_tile(i,6).convert('RGB')).getbbox() is None
    early_position = reel_position(1.7+i*STAGGER,i)
    assert early_position > 0
    assert render_tile(i,0).tobytes() != render_tile(i,early_position).tobytes()
    positions = [reel_position(index/FPS,i) for index in range(N+1)]
    assert all(a <= b for a,b in zip(positions,positions[1:]))
    assert sprite(REELS[i][0],178,'#1673ff').width <= 284
for strip in strips:
    assert strip.crop((MARGIN,0,MARGIN+W,BAND)).tobytes() == strip.crop((MARGIN+PERIOD,0,MARGIN+PERIOD+W,BAND)).tobytes()
manifest = {'renderIdentity': render_identity, 'rendererSourceSha256': hashlib.sha256(renderer_source.encode()).hexdigest(), 'posterSha256': hashlib.sha256((args.output/'poster.png').read_bytes()).hexdigest(), 'schemaVersion': 1, 'status': 'local-review', 'locale': locale, 'currencies': currencies, 'glyphs': [reel[0] for reel in REELS], 'reels': REELS, 'width': W, 'height': H, 'fps': FPS, 'seconds': DURATION, 'frames': N, 'audio': False, 'sessionStarts': SESSION_STARTS, 'sessionDuration': SESSION_DURATION, 'stagger': STAGGER, 'scrollPixelsPerSecond': -SPEED, 'rawEndpointIdentical': True, 'reelReturnIdentical': True, 'rawSampleSha256': samples, 'sourceSha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'fontSha256': hashlib.sha256(FONT.read_bytes()).hexdigest(), 'configSha256': hashlib.sha256((DESIGN / 'header-locales.json').read_bytes()).hexdigest()}
if args.video:
    if not FFMPEG:
        raise SystemExit('ffmpeg is required for video rendering')
    command = [FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-', '-an', '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p', '-color_range', 'tv', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-c:v', 'libx264', '-threads', '4', '-preset', 'fast', '-crf', '17', '-pix_fmt', 'yuv420p', '-bsf:v', 'h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0', '-movflags', '+faststart', str(args.output/'header.mp4')]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    input_hashes = []
    for index in range(N):
        data = frame_image(index).tobytes()
        input_hashes.append(hashlib.sha256(data).hexdigest())
        process.stdin.write(data)
        if index % 180 == 0:
            print(f'{locale or "generic"}: {index}/{N}', flush=True)
    process.stdin.close()
    if process.wait():
        raise SystemExit('ffmpeg failed')

    assert len(set(input_hashes)) == N
    probe = json.loads(subprocess.run([shutil.which('ffprobe'), '-v', 'error', '-count_frames', '-show_streams', '-show_format', '-of', 'json', str(args.output/'header.mp4')], check=True, capture_output=True, text=True).stdout)
    stream = probe['streams'][0]
    assert len(probe['streams']) == 1 and stream['codec_name'] == 'h264'
    assert (stream['width'], stream['height'], stream['nb_read_frames'], stream['r_frame_rate']) == (W,H,str(N),'60/1')
    assert float(probe['format']['duration']) == DURATION
    assert [stream[key] for key in ['color_space','color_transfer','color_primaries']] == ['bt709']*3
    assert stream['color_range'] == 'tv' and stream['pix_fmt'] == 'yuv420p'
    decoded_hashes = subprocess.run([FFMPEG, '-v', 'error', '-i', str(args.output/'header.mp4'), '-f', 'framemd5', '-'], check=True, capture_output=True, text=True).stdout
    decoded_hashes = [line.rsplit(',',1)[-1].strip() for line in decoded_hashes.splitlines() if line and not line.startswith('#')]
    assert len(decoded_hashes) == N and len(set(decoded_hashes)) == N
    manifest.update({'videoComplete': True, 'uniqueDecodedFrames': len(set(decoded_hashes)), 'ffmpeg': subprocess.run([FFMPEG, '-version'], check=True, capture_output=True, text=True).stdout.splitlines()[0], 'probe': probe, 'uniqueInputFrames': len(set(input_hashes)), 'videoSha256': hashlib.sha256((args.output/'header.mp4').read_bytes()).hexdigest(), 'videoBytes': (args.output/'header.mp4').stat().st_size})
(args.output/'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
