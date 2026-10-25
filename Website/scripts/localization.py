from html import escape
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import json, re
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
LOCALES=json.loads((ROOT/'locales/manifest.json').read_text())
SOURCE=json.loads((ROOT/'locales/en-US.json').read_text())

def catalog(locale):
    data=json.loads((ROOT/'locales'/f'{locale}.json').read_text())
    if set(data)!=set(SOURCE) or any(not isinstance(v,str) or not v.strip() for v in data.values()):
        raise ValueError(f'Incomplete translation catalog: {locale}')
    return data

def route(item,page='',prefix='/'):
    return prefix+('/'.join(p for p in [item['path'],page] if p).rstrip('/')+'/').lstrip('/')

def asset(item,name,prefix='/'):
    folder_locale=item['locale'] if name in ['app-store-badge.svg','social.png'] else item['assets']
    localized=ROOT/'assets'/folder_locale/name
    folder=folder_locale+'/' if folder_locale!='en-US' and localized.is_file() else ''
    return prefix+'assets/'+folder+name

def language_code(item):
    return {'uk':'УКР','ru':'РУС','ja':'日本語','ko':'한국어','zh-Hans':'简中','zh-Hant':'繁中'}.get(item['locale'],item['locale'].split('-')[0].upper())


def language_menu(item,page,prefix,data):
    links=''.join('<a href="'+route(other,page,prefix)+'" lang="'+other['locale']+'" hreflang="'+other['locale']+'" aria-label="'+escape(other['name'],quote=True)+'" title="'+escape(other['name'],quote=True)+'"'+(' aria-current="page"' if other==item else '')+'>'+escape(other['name'])+'</a>' for other in LOCALES)
    code=language_code(item)
    if item['locale'].startswith('en-'):code='EN'
    return '<details class="language-menu"><summary aria-label="'+escape(data['Language']+': '+item['name'],quote=True)+'">'+code+'</summary><nav aria-label="'+escape(data['Choose your language'],quote=True)+'">'+links+'</nav></details>'

class LocalizedHTML(HTMLParser):
    def __init__(self,item,page,prefix):
        super().__init__(convert_charrefs=True)
        self.item=item;self.page=page;self.prefix=prefix;self.data=catalog(item['locale']);self.parts=[];self.skip=False
    def text(self,text):
        key=' '.join(text.split())
        if key not in SOURCE and not re.fullmatch(r'[↗←→↓⌘◉♡]+',key):
            raise ValueError('Add this source text to every locale catalog: '+key)
        return self.data.get(key,key)
    def url(self,value):
        if value.startswith('#'):
            return route(self.item,self.page,self.prefix)+value
        if value.startswith(('https:','http:','mailto:','data:')):return value
        clean=value.removeprefix('../')
        if clean.startswith('assets/'):return asset(self.item,clean[7:],self.prefix)
        if clean.startswith(('style.css','legal.css','calculator.css','landing.js','calculator.js')):return self.prefix+clean
        if clean in ['support/','support/index.html']:return route(self.item,'support',self.prefix)
        if clean in ['privacy/','terms/']:return self.prefix+clean
        if value in ['../','./']:return route(self.item,'',self.prefix)
        return value
    def handle_starttag(self,tag,attrs):
        values=dict(attrs)
        if tag in ['script','style']:self.skip=True
        if tag=='html':values['lang']=self.item['locale']
        for key in ['alt','aria-label','data-image-alt']:
            if values.get(key):values[key]=self.text(values[key])
        if tag=='meta' and values.get('name',values.get('property')) in ['description','og:title','og:description']:
            values['content']=self.text(values['content'])
        for key in ['src','href','data-image']:
            if values.get(key):values[key]=self.url(values[key])
        if tag=='img' and values.get('src','').endswith('app-store-badge.svg'):
            badge=ET.parse(ROOT/values['src'].removeprefix(self.prefix)).getroot()
            width,height=map(float,badge.get('viewBox').split()[2:])
            values['width']=str(round(48*width/height));values['height']='48'
        self.parts.append('<'+tag+''.join(' '+key+('="'+escape(value,quote=True)+'"' if value is not None else '') for key,value in values.items())+'>')
    def handle_endtag(self,tag):
        if tag=='head' and self.page=='':
            background=asset(self.item,'phone-screen.webp',self.prefix)
            self.parts.append('<style>.calculator-stand{background-image:url("'+background+'")}</style>')
        if tag=='body' and self.page=='':
            keys=['Interactive currency calculator, sample rates','Calculator keypad','Delete last digit','Clear amount','Decimal point','Euro','US dollar','British pound','Czech koruna','Japanese yen','Swiss franc','Selected input currency.','Select as input currency.']
            payload={'locale':self.item['locale'],'strings':{key:self.data[key] for key in keys}}
            self.parts.append('<script type="application/json" id="calculator-copy">'+json.dumps(payload,ensure_ascii=False).replace('<',r'\u003c')+'</script>')
        self.parts.append('</'+tag+'>')
        if tag in ['script','style']:self.skip=False
    def handle_startendtag(self,tag,attrs):self.handle_starttag(tag,attrs)
    def handle_data(self,text):
        if self.skip or not text.strip():self.parts.append(text);return
        prefix=re.match(r'^\s*',text)[0];suffix=re.search(r'\s*$',text)[0]
        self.parts.append(prefix+escape(self.text(text),quote=False)+suffix)
    def handle_entityref(self,name):
        from html import unescape
        self.handle_data(unescape('&'+name+';'))
    def handle_charref(self,name):
        from html import unescape
        self.handle_data(unescape('&#'+name+';'))
    def handle_comment(self,text):
        self.parts.append(language_menu(self.item,self.page,self.prefix,self.data) if text.strip()=='language-picker' else '<!--'+text+'-->')
    def handle_decl(self,text):self.parts.append('<!'+text+'>')

def localize(source,item,page,prefix='/'):
    parser=LocalizedHTML(item,page,prefix);parser.feed(source);return ''.join(parser.parts)
