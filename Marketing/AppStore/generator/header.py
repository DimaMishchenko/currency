from pathlib import Path
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont, ImageChops
import argparse, math, shutil, subprocess, xml.etree.ElementTree as ET
from generate import DESIGN, load, verified_object

parser = argparse.ArgumentParser(description='Render the fifteen second H09 currency header from frozen design geometry.')
parser.add_argument('--inputs', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--video', action='store_true')
args = parser.parse_args()
SOURCE = DESIGN / 'header.svg'
FONT = verified_object(args.inputs, 'bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207', load(DESIGN / 'input-manifest.json')['objects'])
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
    return im.resize((round(im.width/2),round(im.height/2)),Image.Resampling.LANCZOS)

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

def frame_image(frame):
    return image_at_offset(offset(frame),(frame%N)/FPS)

def image_at_offset(scroll_offset,t=0):
    im=background.copy()
    for row,strip in zip(rows,strips):
        band=strip.transform((W,BAND),Image.Transform.AFFINE,(1,0,MARGIN+scroll_offset,0,1,0),resample=Image.Resampling.BICUBIC).convert('RGBA')
        y=round(float(row[0].get('y'))-BAND/2)
        im.paste(band,(0,y),band)
    for i,(reel,x,y) in enumerate(focal):
        position=reel_position(t,i)
        tile=settled_tile(i,int(position)) if position in (0,3,6) else render_tile(i,position)
        im.paste(tile,(x,y),tile)
    return im

args.output.mkdir(parents=True, exist_ok=True)
frame_image(0).resize((1280,549),Image.Resampling.LANCZOS).save(args.output/'poster.png')
if args.video:
    if not FFMPEG:
        raise SystemExit('ffmpeg is required for video rendering')
    command = [FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-', '-an', '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p', '-color_range', 'tv', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-c:v', 'libx264', '-threads', '4', '-preset', 'fast', '-crf', '17', '-pix_fmt', 'yuv420p', '-bsf:v', 'h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0', '-movflags', '+faststart', str(args.output/'header.mp4')]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    for index in range(N):
        process.stdin.write(frame_image(index).tobytes())
    process.stdin.close()
    if process.wait():
        raise SystemExit('ffmpeg failed')
