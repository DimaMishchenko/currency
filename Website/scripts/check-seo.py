"""Validate crawlability, locale routing, translation coverage and generated SEO metadata."""
from pathlib import Path
from html.parser import HTMLParser
from html import unescape
from urllib.parse import urljoin,urlsplit,unquote
from urllib.robotparser import RobotFileParser
import argparse,json,re
import xml.etree.ElementTree as ET
from localization import LOCALES,catalog,route

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--directory',type=Path,required=True)
parser.add_argument('--base-url',default='https://currency.dimasike.com/')
parser.add_argument('--production',action='store_true')
args=parser.parse_args();root=args.directory.resolve();base=args.base_url.rstrip('/')+'/'
prefix=urlsplit(base).path

class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.meta={};self.canon=[];self.alternates={};self.h1=0;self.links=[];self.json=[];self.ids=set();self.lang='';self._json=False;self._parts=[]
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='html':self.lang=attrs.get('lang','')
        if tag=='h1':self.h1+=1
        if attrs.get('id'):self.ids.add(attrs['id'])
        if tag=='meta':self.meta[attrs.get('name',attrs.get('property'))]=attrs.get('content','')
        if tag=='link' and attrs.get('rel')=='canonical':self.canon.append(attrs['href'])
        if tag=='link' and attrs.get('rel')=='alternate':self.alternates[attrs['hreflang']]=attrs['href']
        if tag in ['a','link','script','img','button']:
            for key in ['href','src','data-image']:
                if attrs.get(key):self.links.append(attrs[key])
        if tag=='img':
            assert 'alt' in attrs,'Image missing alt'
            assert int(attrs.get('width','0'))>0 and int(attrs.get('height','0'))>0,'Image missing dimensions'
        if tag=='script' and attrs.get('type')=='application/ld+json':self._json=True;self._parts=[]
    def handle_endtag(self,tag):
        if tag=='script' and self._json:self.json.append(json.loads(''.join(self._parts)));self._json=False
    def handle_data(self,text):
        if self._json:self._parts.append(text)

native_locales={locale for text in json.loads((Path(__file__).resolve().parents[2]/'Apps/Currency/App/Resources/Localizable.xcstrings').read_text())['strings'].values() for locale in text.get('localizations',{})}
store_locales=set(json.loads((Path(__file__).resolve().parents[2]/'Marketing/AppStore/metadata.json').read_text())['locales'])
assert {locale.split('-')[0] for locale in store_locales} <= {item['locale'].split('-')[0] for item in LOCALES},'Website is missing an App Store language'
assert all(any(item['locale']==locale or item['locale'].split('-')[0]==locale for item in LOCALES) for locale in native_locales),'Website is missing an app language'

entries=[(item,kind,route(item,kind,'/').lstrip('/')) for item in LOCALES for kind in ['','support']]
entries += [(LOCALES[0],kind,kind+'/') for kind in ['privacy','terms']]
parsed={}
for item,kind,path in entries:
    catalog(item['locale'])
    source=(root/path/'index.html').read_text();page=Page();page.feed(source);parsed[path]=page
    assert re.search(r'<title>\S.*?</title>',source,re.S),path+': missing title'
    assert page.meta.get('description'),path+': missing description'
    assert page.h1==1,path+': expected one H1'
    assert '<!-- canonical-policy:' not in source,'Unrendered policy'
    header=re.search(r'<header\b.*?</header>',source,re.S)[0]
    footer=re.search(r'<footer\b.*?</footer>',source,re.S)[0]
    assert header.count('class="language-menu"')==1,path+': picker must be in header'
    assert 'language-menu' not in footer and 'legal-footer-brand' not in footer,path+': redundant footer elements'
    assert all('>'+other['name']+'</a>' in header for other in LOCALES),path+': missing native language names'
    if kind in ['','support']:
        assert page.lang==item['locale'],path+': incorrect document language'
        assert source.count('class="language-menu"')==1,path+': missing language picker'
        assert all(route(other,kind,prefix) in page.links for other in LOCALES),path+': missing language navigation'
        if kind=='':
            assert source.count('data-rate-panel=')==3
            assert len(re.findall(r'data-image="',source))==3
            payload=json.loads(re.search(r'<script type="application/json" id="calculator-copy">(.*?)</script>',source,re.S)[1])
            assert payload['locale']==item['locale']
        else:
            assert source.count('class="setup-guide"')==4,path+': missing illustrated guide'
            assert all(id in page.ids for id in ['home-screen','configure','smart-stack','watch-face'])
    canonical=urljoin(base,path)
    if args.production:
        assert page.canon==[canonical],path+': incorrect canonical'
        assert 'noindex' not in page.meta.get('robots','')
        assert 'index,follow' in page.meta.get('robots','')
        assert page.meta['og:url']==canonical
        assert page.meta['og:description']==page.meta['description']
        assert page.meta['twitter:card']=='summary_large_image'
        assert page.meta['twitter:description']==page.meta['description']
        assert len(page.json)==1
        assert any(n['@type']=='WebPage' and n['url']==canonical and n['inLanguage']==item['locale'] for n in page.json[0]['@graph'])
        if kind in ['','support']:
            expected={other['locale']:urljoin(base,route(other,kind,prefix)) for other in LOCALES}
            expected['x-default']=urljoin(base,route(LOCALES[0],kind,prefix))
            assert page.alternates==expected,path+': incomplete hreflang cluster'
        else:assert not page.alternates
        if kind=='':
            app=next(n for n in page.json[0]['@graph'] if n['@type']=='MobileApplication')
            assert app['offers']['price']=='0' and app['isAccessibleForFree']
            assert 'aggregateRating' not in app and 'review' not in app
            assert app['softwareHelp']['url']==urljoin(base,route(item,'support',prefix))
    else:
        assert 'noindex' in page.meta.get('robots','')
        assert not page.canon and not page.json and not page.alternates,'Preview claims production identity'
    for value in page.links:
        url=urlsplit(urljoin(base+path,value))
        if url.scheme not in ['http','https'] or url.netloc!=urlsplit(base).netloc:continue
        if not url.path.startswith(prefix):continue
        local=root/unquote(url.path[len(prefix):])
        if url.path.endswith('/'):local/='index.html'
        assert local.is_file(),path+': missing link/asset '+value

if args.production:
    assert not (root/'review').exists(),'Do not deploy browser review frames'
    ns={'s':'http://www.sitemaps.org/schemas/sitemap/0.9'}
    urls=[node.text for node in ET.parse(root/'sitemap.xml').findall('s:url/s:loc',ns)]
    assert len(urls)==len(entries) and set(urls)=={urljoin(base,path) for _,_,path in entries}
    assert 'Sitemap: '+urljoin(base,'sitemap.xml') in (root/'robots.txt').read_text()
    for item in LOCALES:
        folder=root/'assets'/(item['locale'] if item['locale']!='en-US' else '')
        assert (folder/'social.png').is_file(),'Missing localized social preview'
        assert (folder/'app-store-badge.svg').is_file(),'Missing official localized download badge'
        if item['assets']=='en-US':continue
        for name in ['phone.webp','phone-screen.webp','converter.webp','crypto.webp','metals.webp','offline.webp','watch.webp','watch-history.webp','watch-stack.webp','watch-face.webp','widget-history.webp','widget-cash.webp','widget-board.webp','widget-pocket.webp','ipad-widgets.webp','duo-widgets.webp','calculator-reference.webp']:
            assert (root/'assets'/item['assets']/name).is_file(),'Missing localized native asset: '+item['locale']+'/'+name
else:assert not (root/'sitemap.xml').exists()
robots=RobotFileParser();robots.parse((root/'robots.txt').read_text().splitlines())
for agent in ['Googlebot','bingbot','OAI-SearchBot','Claude-SearchBot','PerplexityBot']:
    assert robots.can_fetch(agent,base)==args.production,agent+': incorrect access'
    for _,_,path in entries:assert robots.can_fetch(agent,urljoin(base,path))==args.production
print(f'PASS: {len(LOCALES)} locale variants, {len(entries)} pages, '+('self-canonicals, reciprocal hreflang, structured data, sitemap, localized assets and search/AI crawl access' if args.production else 'preview isolation')+', translation coverage, language links and illustrated guides')
