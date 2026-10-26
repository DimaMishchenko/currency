from pathlib import Path
import argparse,json

parser=argparse.ArgumentParser(description='Prepare isolated viewport copies for browser review.')
parser.add_argument('--site-dir',type=Path,default=Path(__file__).resolve().parents[1]/'.local/dist')
parser.add_argument('--all-locales',action='store_true')
args=parser.parse_args()
root=args.site_dir.resolve()
if not (root/'index.html').is_file():parser.error('Build the website first.')
review=root/'review';review.mkdir(exist_ok=True)
entries=[('','',root/'index.html')]
if args.all_locales:
    manifest=json.loads((Path(__file__).resolve().parents[1]/'locales/manifest.json').read_text())
    entries=[(item['locale'],kind,root/item['path']/kind/'index.html') for item in manifest for kind in ['','support']]
metrics='''<script>addEventListener('load',()=>requestAnimationFrame(()=>{const phone=document.querySelector('.hero-phone');const r={width:innerWidth,height:innerHeight,content:document.documentElement.scrollWidth,overflow:document.documentElement.scrollWidth>innerWidth,pageHeight:document.documentElement.scrollHeight,h1:document.querySelectorAll('h1').length,font:document.fonts.check('780 20px Nunito'),phoneBottom:phone?Math.round(phone.getBoundingClientRect().bottom):null,unlabeledButtons:[...document.querySelectorAll('button')].filter(b=>!b.textContent.trim()&&!b.getAttribute('aria-label')).length,brokenImages:[...document.images].filter(i=>!i.naturalWidth&&i.loading!=='lazy').map(i=>i.src)};parent.postMessage({currencyReview:r},location.origin);}));</script>'''
count=0
for locale,kind,source in entries:
    stem='-'.join(p for p in [locale,kind] if p)
    content='content'+('-'+stem if stem else '')+'.html'
    html=source.read_text().replace('<head>','<head><base href="../">',1)
    (review/content).write_text(html.replace('</body>',metrics+'</body>'))
    anchors=[''] if args.all_locales else ['', 'calculator', 'widgets', 'rates', 'watch', 'tablets', 'facts']
    for width in [320,390,768,1024,1280]:
        height=844 if width<700 else 680
        for anchor in anchors:
            name='-'.join(p for p in [stem,str(width),anchor] if p)+'.html'
            scale='position:absolute;left:50%;top:35px;transform:translateX(-50%) scale(.76);transform-origin:top center;' if width<700 else ''
            page=f'''<!doctype html><html><head><meta charset="utf-8"><meta name="robots" content="noindex,nofollow"><title>Currency {locale} {kind} {width}px review</title><style>body{{margin:0;background:#e5eafa;display:grid;justify-content:center}}iframe{{width:{width}px;height:{height}px;border:0;{scale}}}output{{font:10px monospace;text-align:center;margin:10px}}[hidden]{{display:none}}</style></head><body><output role="status" data-testid="layout-result" hidden></output><iframe title="{width}px website" src="{content}{'#'+anchor if anchor else ''}"></iframe><script>addEventListener('message',e=>{{if(e.origin!==location.origin||!e.data.currencyReview)return;const o=document.querySelector('output');o.textContent=JSON.stringify(e.data.currencyReview);o.hidden=false;}});</script></body></html>'''
            (review/name).write_text(page);count+=1
print(f'Prepared {count} viewport review frames in {review}')
