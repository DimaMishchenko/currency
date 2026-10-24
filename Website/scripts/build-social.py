from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

root=Path(__file__).resolve().parents[2]
website=root/'Website'
manifest=json.loads((website/'locales/manifest.json').read_text())
recipe=json.loads((root/'Marketing/AppStore/design/recipe.json').read_text())
inputs=root/'Marketing/AppStore/generator/.local/inputs/objects'
for item in manifest:
    locale=item['locale'];copy=json.loads((website/'locales'/f'{locale}.json').read_text())
    directory=website/'assets'/(locale if locale!='en-US' else '')
    directory.mkdir(exist_ok=True)
    if locale=='et':
        fontfile=website/'assets/Nunito.ttf';face=0;axes=[800]
    else:
        placement=next(p for p in recipe['placements'] if p['locale']==locale and p['family']=='default' and p['profile']=='iphone' and p['order']==1)
        fontspec=recipe['masters'][placement['master']]['headlines'][0]
        fontfile=inputs/fontspec['font'];face=fontspec['face'];axes=fontspec['axes']
    def font(size):
        result=ImageFont.truetype(str(fontfile),size,index=face)
        if axes:result.set_variation_by_axes(axes)
        return result
    im=Image.new('RGB',(1200,630),'#f7f9ff');draw=ImageDraw.Draw(im)
    icon=Image.open(website/'assets/icon.png').convert('RGBA').resize((75,75),Image.Resampling.LANCZOS);im.paste(icon,(60,57),icon)
    draw.text((155,68),'Currency',font=ImageFont.truetype(str(website/'assets/Nunito.ttf'),40),fill='#172034')
    for text,y,color in [(copy['Convert with'],190,'#172034'),(copy['widgets'],300,'#0075f5')]:
        size=90
        while draw.textbbox((0,0),text,font=font(size))[2]>710:size-=1
        draw.text((60,y),text,font=font(size),fill=color)
    text=copy['Free forever'];size=30
    while draw.textbbox((0,0),text,font=font(size))[2]>700:size-=1
    draw.text((65,485),text,font=font(size),fill='#0061cf')
    phone=website/'assets'/('' if item['assets']=='en-US' else item['assets'])/'phone.webp'
    if not phone.is_file():raise FileNotFoundError('Export native assets first: '+str(phone))
    art=Image.open(phone).convert('RGBA');art.thumbnail((300,560),Image.Resampling.LANCZOS);im.paste(art,(855,40),art)
    im.save(directory/'social.png',optimize=True)
    print('Social preview ready: '+locale,flush=True)
