from pathlib import Path
from urllib.parse import urlsplit, urljoin
from xml.sax.saxutils import escape
import argparse, hashlib, json, re, shutil
from html import unescape, escape as html_escape
from localization import LOCALES, SOURCE, catalog, localize, route, asset, language_menu

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Build the static Currency website without hosted services or tracking.')
parser.add_argument('--output',type=Path,default=root/'.local/dist')
parser.add_argument('--base-url',default='https://currency.dimasike.com/')
parser.add_argument('--production',action='store_true')
args=parser.parse_args()
base=args.base_url.rstrip('/')+'/' if args.base_url else ''
if args.production:
    parsed=urlsplit(base)
    if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        parser.error('Production requires a public HTTPS --base-url with no credentials, query or fragment.')
out=args.output.resolve()
if out==root or root.is_relative_to(out):parser.error('Output cannot replace the source directory or its parents.')
if out.is_relative_to(root) and not out.is_relative_to(root/'.local'):parser.error('Outputs inside Website must stay in .local/.')
if args.production and (out/'review').exists():parser.error('Choose a fresh production output directory; this output contains browser review frames.')
out.mkdir(parents=True,exist_ok=True)

def render_policy(name):
    documentation=root.parent/'Documentation'
    source=documentation/name
    if name not in {'PrivacyPolicy.md','TermsOfUse.md'}:raise ValueError('Unknown canonical policy')
    def inline(text):
        text=escape(text)
        def link(match):
            label,target=match.groups()
            if target=='PrivacyPolicy.md':target='../privacy/'
            elif not target.startswith(('https://','mailto:')):
                from posixpath import normpath
                path=normpath('Documentation/'+target)
                kind='tree' if (root.parent/path).is_dir() else 'blob'
                target='https://github.com/DimaMishchenko/currency/'+kind+'/main/'+path
            return '<a href="'+target+'">'+label+'</a>'
        text=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',link,text)
        return re.sub(r'\*\*(.+?)\*\*',r'<strong>\1</strong>',text)
    paragraphs=[]
    for block in source.read_text().strip().split('\n\n'):
        if block.startswith('# '):paragraphs.append('<h1>'+inline(block[2:])+'</h1>')
        else:
            css=' class="legal-effective"' if block.startswith('Effective ') else ''
            paragraphs.append('<p'+css+'>'+inline(block)+'</p>')
    return '\n    '.join(paragraphs)

prefix=urlsplit(base).path or '/'
if not prefix.endswith('/'):prefix+='/'
allowed={'.css','.js','.webp','.png','.ttf','.txt','.svg'}
for p in root.rglob('*'):
    relative=p.relative_to(root)
    if any(part.startswith('.') or part in {'scripts','tests','locales'} for part in relative.parts):continue
    if not p.is_file() or p.suffix not in allowed:continue
    target=out/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)

pages=[]
for item in LOCALES:
    for kind in ['','support']:
        pages.append((item,kind,root/(kind or '.')/'index.html'))
for kind in ['privacy','terms']:pages.append((LOCALES[0],kind,root/kind/'index.html'))

for item,kind,p in pages:
    path=route(item,kind,'/').lstrip('/') if kind in ['','support'] else kind+'/'
    target=out/path/'index.html';target.parent.mkdir(parents=True,exist_ok=True)
    s=p.read_text()
    s=re.sub(r'<!-- canonical-policy:([A-Za-z]+\.md) -->',lambda m:render_policy(m[1]),s)
    def version(match):
        name=match[1].split('?')[0];source=(p.parent/name).resolve()
        if not source.is_file() or not source.is_relative_to(root):return match[0]
        digest=hashlib.sha256(source.read_bytes()).hexdigest()[:10]
        return ('href' if match[0].startswith('href') else 'src')+'="'+name+'?v='+digest+'"'
    s=re.sub(r'(?:href|src)="([^"?]+(?:\?v=[a-z0-9]+)?)"',lambda m:version(m) if m[1].split('?')[0].endswith(('.css','.js')) else m[0],s)
    if kind in ['','support']:s=localize(s,item,kind,prefix)
    else:s=s.replace('<!-- language-picker -->',language_menu(item,'',prefix,catalog(item['locale'])))
    if args.production:
        canonical=urljoin(base,path)
        data=catalog(item['locale'])
        title=unescape(re.search(r'<title>(.*?)</title>',s,re.S)[1])
        description=unescape(re.search(r'<meta name="description" content="([^"]+)"',s)[1])
        s=re.sub(r'<meta (?:name|property)="(?:robots|og:[^\"]+|twitter:[^\"]+)"[^>]*>','',s)
        social=asset(item,'social.png',prefix)
        image=urljoin(base,social)
        image_alt=data['Currency on your Home Screen']
        metadata={'og:type':'website','og:site_name':'Currency','og:locale':item['ogLocale'],'og:title':title,'og:description':description,'og:url':canonical,'og:image':image,'og:image:type':'image/png','og:image:width':'1200','og:image:height':'630','og:image:alt':image_alt,'twitter:card':'summary_large_image','twitter:title':title,'twitter:description':description,'twitter:image':image,'twitter:image:alt':image_alt}
        additions='<meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">'
        additions+='<link rel="canonical" href="'+html_escape(canonical,quote=True)+'">'
        if kind in ['','support']:
            for other in LOCALES:
                url=urljoin(base,route(other,kind,prefix))
                additions+='<link rel="alternate" hreflang="'+other['locale']+'" href="'+html_escape(url,quote=True)+'">'
            additions+='<link rel="alternate" hreflang="x-default" href="'+html_escape(urljoin(base,route(LOCALES[0],kind,prefix)),quote=True)+'">'
            for other in LOCALES:
                if other!=item:additions+='<meta property="og:locale:alternate" content="'+other['ogLocale']+'">'
        for key,value in metadata.items():
            attribute='property' if key.startswith('og:') else 'name'
            additions+='<meta '+attribute+'="'+key+'" content="'+html_escape(value,quote=True)+'">'
        website={'@type':'WebSite','@id':base+'#website','url':base,'name':'Currency','alternateName':'Currency Converter & Widgets','inLanguage':[locale['locale'] for locale in LOCALES]}
        page={'@type':'WebPage','@id':canonical+'#webpage','url':canonical,'name':title,'description':description,'inLanguage':item['locale'],'isPartOf':{'@id':base+'#website'},'about':{'@id':base+'#app'}}
        graph=[website,page]
        if kind=='':
            page['mainEntity']={'@id':base+'#app'}
            graph.append({'@type':'MobileApplication','@id':base+'#app','name':'Currency','url':canonical,'inLanguage':item['locale'],'applicationCategory':'FinanceApplication','operatingSystem':'iOS, iPadOS, watchOS','description':description,'image':image,'isAccessibleForFree':True,'downloadUrl':'https://apps.apple.com/app/id6816213577','softwareHelp':{'@type':'WebPage','url':urljoin(base,route(item,'support',prefix))},'screenshot':[urljoin(base,asset(item,name+'.webp',prefix)) for name in ['phone','watch','converter']],'offers':{'@type':'Offer','price':'0','priceCurrency':'USD','url':'https://apps.apple.com/app/id6816213577'},'sameAs':['https://github.com/DimaMishchenko/currency','https://apps.apple.com/app/id6816213577']})
        structured=json.dumps({'@context':'https://schema.org','@graph':graph},separators=(',',':'),ensure_ascii=False).replace('<',r'\u003c')
        additions+='<script type="application/ld+json">'+structured+'</script>'
        s=s.replace('</head>',additions+'</head>')
    target.write_text(s)
if args.production:
    locations=[route(item,kind,'/').lstrip('/') if kind in ['','support'] else kind+'/' for item,kind,_ in pages]
    xml='<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join('<url><loc>'+escape(urljoin(base,path))+'</loc></url>' for path in locations)+'</urlset>'
    (out/'sitemap.xml').write_text(xml+'\n')
    (out/'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: '+urljoin(base,'sitemap.xml')+'\n')
else:
    (out/'sitemap.xml').unlink(missing_ok=True)
    (out/'robots.txt').write_text('User-agent: *\nDisallow: /\n')
print(json.dumps({'output':str(out),'production':args.production,'pages':len(pages),'locales':len(LOCALES),'canonicalBase':base or None}))
