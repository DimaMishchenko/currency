from pathlib import Path
import argparse, base64, io, json, shutil, subprocess
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

parser=argparse.ArgumentParser(description='Extract native app visuals from the approved App Store generator inputs.')
parser.add_argument('--inputs',type=Path,default=Path('Marketing/AppStore/generator/.local/inputs/objects'))
parser.add_argument('--locale',default='en-US')
args=parser.parse_args()
repo=Path(__file__).resolve().parents[2]
assets=repo/'Website/assets'
if args.locale!='en-US':assets/=args.locale
assets.mkdir(parents=True,exist_ok=True)
recipe=json.loads((repo/'Marketing/AppStore/design/recipe.json').read_text())
ns='{http://www.w3.org/2000/svg}'
ET.register_namespace('',ns[1:-1])
def master(family='default',profile='iphone',order=1):
 p=next(p for p in recipe['placements'] if p['locale']==args.locale and p['family']==family and p['profile']==profile and p['order']==order)
 return recipe['masters'][p['master']]
def source(spec,index):return args.inputs/spec['images'][index]
def tree(spec):
 root=ET.parse(repo/'Marketing/AppStore/design'/spec['template']).getroot()
 for n in list(root):
  if n.tag==ns+'rect':root.remove(n)
 for im in root.iter(ns+'image'):
  slot=int(im.attrib['href'].removeprefix('slot:')); data=source(spec,slot).read_bytes()
  im.set('href','data:image/png;base64,'+base64.b64encode(data).decode())
 return root

def raster(root,name,width,height):
 root.set('width',str(width));root.set('height',str(height))
 png=subprocess.run(['rsvg-convert','--unlimited'],input=ET.tostring(root),stdout=subprocess.PIPE,check=True).stdout
 Image.open(io.BytesIO(png)).save(assets/(name+'.webp'),quality=92,method=6)

def device(name,spec,box):
 root=tree(spec);root.set('viewBox',' '.join(map(str,box)))
 raster(root,name,700,round(700*box[3]/box[2]))

for name,family,order in [('phone','default',1),('converter','default',3),('offline','default',4),('history','default',5),('crypto','crypto',1),('metals','metals',1)]:
 device(name,master(family=family,order=order),(98,500,1010,2061.22))
watch=master(order=6);device('watch',watch,(153,795,900,1414.3))
Image.open(source(master(),1)).save(assets/'phone-screen.webp',quality=94,method=6)
Image.open(source(watch,1)).save(assets/'watch-screen.webp',quality=95,method=6)

for name,order in [('watch-history',2),('watch-stack',3),('watch-face',4)]:
    raw=master(profile='watch',order=order)['native']
    framed=dict(watch);framed['images']=list(watch['images']);framed['images'][1]=raw
    device(name,framed,(153,795,900,1414.3))
for profile,width,height in [('ipad',2300,3000),('duo-inner',3093,2247)]:
    root=tree(master(profile=profile,order=1))
    first=root.find(ns+'g');first.attrib.pop('transform',None)
    for child in list(root):
        if child is not first and child.tag!=ns+'defs':root.remove(child)
    root.set('viewBox',f'0 0 {width} {height}')
    raster(root,'ipad' if profile=='ipad' else 'duo',1000,round(1000*height/width))

collection=master(order=2)
root=tree(collection)
for name in ('pocket','board','cash','history'):
 mask=next(n for n in root.iter(ns+'mask') if n.get('id')=='widget-'+name)
 box=tuple(float(mask.get(k)) for k in ('x','y','width','height'))
 cropped=tree(collection);cropped.set('viewBox',' '.join(map(str,box)))
 for g in cropped.iter(ns+'g'):g.attrib.pop('filter',None)
 raster(cropped,'widget-'+name,640,round(640*box[3]/box[2]))
Image.open(source(master(),1)).crop((91,280,1229,1468)).save(assets/'calculator-reference.webp',quality=96)
if args.locale!='en-US':
    print('Extracted approved native assets for '+args.locale)
    raise SystemExit(0)
shutil.copy2(repo/'Marketing/Icons/Fonts/Nunito.ttf',assets/'Nunito.ttf')
shutil.copy2(repo/'Marketing/AppStore/design/Nunito-OFL.txt',assets/'Nunito-OFL.txt')
print('Extracted approved native phone, Watch, widgets and screens. No screenshot UI redrawn.')

p=assets;im=Image.new('RGB',(1200,630),'#f7f9ff');d=ImageDraw.Draw(im)
def font(size,weight):
 f=ImageFont.truetype(str(p/'Nunito.ttf'),size);f.set_variation_by_axes([weight]);return f
icon=Image.open(p/'icon.png').convert('RGBA').resize((75,75),Image.Resampling.LANCZOS);im.paste(icon,(60,57),icon)
d.text((155,68),'Currency',font=font(40,800),fill='#172034')
d.text((60,180),'Convert with',font=font(90,800),fill='#172034');d.text((60,278),'widgets.',font=font(90,800),fill='#0075f5')
d.text((64,437),'160 currencies · Crypto & metals · Works offline',font=font(24,600),fill='#566176')
d.rounded_rectangle((62,508,251,554),radius=23,fill='#e6efff');d.text((82,516),'Free forever',font=font(24,800),fill='#0061cf')
phone=Image.open(p/'phone.webp').convert('RGBA');phone.thumbnail((300,560),Image.Resampling.LANCZOS);im.paste(phone,(855,40),phone)
im.save(p/'social.png',optimize=True)
