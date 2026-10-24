"""Build website-only Home Screen illustrations from native widgets and official frames.

Run build-assets.py first. These are illustrative arrangements, not new app captures.
"""
from pathlib import Path
import argparse, base64, json, subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--inputs', type=Path, default=Path('Marketing/AppStore/generator/.local/inputs/objects'))
parser.add_argument('--locale', default='en-US')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
assets = repo / 'Website/assets'
if args.locale != 'en-US': assets /= args.locale
recipe = json.loads((repo / 'Marketing/AppStore/design/recipe.json').read_text())
ns = '{http://www.w3.org/2000/svg}'
ET.register_namespace('', ns[1:-1])

def image(path, x, y, width, height):
    mime = 'image/webp' if path.suffix == '.webp' else 'image/png'
    data = base64.b64encode(path.read_bytes()).decode()
    return f'<image href="data:{mime};base64,{data}" x="{x}" y="{y}" width="{width}" height="{height}"/>'

def scene(width, height, items):
    parts = []
    for name, x, y, w, h in items:
        artwork = image(assets / name, x, y, w, h)
        if name == 'calculator-reference.webp':
            artwork = f'<defs><clipPath id="calculator-round"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{w*.079}"/></clipPath></defs><g clip-path="url(#calculator-round)">{artwork}</g>'
        parts.append(artwork)
    body = ''.join(parts)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"><defs><linearGradient id="wall" x2="1" y2="1"><stop stop-color="#eee2d1"/><stop offset=".48" stop-color="#cbdcf0"/><stop offset="1" stop-color="#7195c6"/></linearGradient></defs><rect width="100%" height="100%" fill="url(#wall)"/>{body}</svg>'''.encode()

profiles = [
 ('ipad', 2064, 2752, 2300, 3000, [
  ('widget-history.webp', 280, 190, 1504, 705),
  ('widget-board.webp', 280, 1050, 700, 700),
  ('widget-pocket.webp', 1084, 1050, 700, 700),
  ('widget-cash.webp', 280, 1935, 1504, 705),
 ]),
 ('duo-inner', 2853, 2007, 3093, 2247, [
  ('calculator-reference.webp', 170, 350, 1000, 1044),
  ('widget-history.webp', 1340, 200, 1340, 628),
  ('widget-board.webp', 1340, 1030, 620, 620),
  ('widget-pocket.webp', 2060, 1030, 620, 620),
 ]),
]
for profile, width, height, fw, fh, items in profiles:
    placement = next(p for p in recipe['placements'] if p['locale']==args.locale and p['family']=='default' and p['profile']==profile and p['order']==1)
    spec = recipe['masters'][placement['master']]
    root = ET.parse(repo/'Marketing/AppStore/design'/spec['template']).getroot()
    group = root.find(ns+'g')
    group.attrib.pop('transform', None)
    for child in list(root):
        if child is not group and child.tag != ns+'defs': root.remove(child)
    screen_slot = 0 if profile=='ipad' else 1
    for node in root.iter(ns+'image'):
        slot = int(node.attrib['href'].removeprefix('slot:'))
        if slot == screen_slot:
            png = subprocess.run(['rsvg-convert','--unlimited'],input=scene(width,height,items),stdout=subprocess.PIPE,check=True).stdout
            data = png
        else:
            data = (args.inputs / spec['images'][slot]).read_bytes()
        node.set('href','data:image/png;base64,'+base64.b64encode(data).decode())
    root.set('viewBox',f'0 0 {fw} {fh}')
    root.set('width','1000');root.set('height',str(round(1000*fh/fw)))
    png = subprocess.run(['rsvg-convert','--unlimited'],input=ET.tostring(root),stdout=subprocess.PIPE,check=True).stdout
    from PIL import Image
    import io
    Image.open(io.BytesIO(png)).save(assets/('ipad-widgets.webp' if profile=='ipad' else 'duo-widgets.webp'),quality=94,method=6)
print('Built website iPad/Duo widget compositions using approved native artwork and frames.')
