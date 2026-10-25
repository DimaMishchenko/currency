from pathlib import Path
import argparse, base64, io, json, shutil, subprocess
import xml.etree.ElementTree as ET
from PIL import Image

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

for name,family,order in [('phone','default',1),('converter','default',3),('offline','default',4),('crypto','crypto',1),('metals','metals',1)]:
 device(name,master(family=family,order=order),(98,500,1010,2061.22))
watch=master(order=6);device('watch',watch,(153,795,900,1414.3))
Image.open(source(master(),1)).save(assets/'phone-screen.webp',quality=94,method=6)

for name,order in [('watch-history',2),('watch-stack',3),('watch-face',4)]:
    raw=master(profile='watch',order=order)['native']
    framed=dict(watch);framed['images']=list(watch['images']);framed['images'][1]=raw
    device(name,framed,(153,795,900,1414.3))

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
