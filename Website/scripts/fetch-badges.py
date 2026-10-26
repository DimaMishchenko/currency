from pathlib import Path
import urllib.request, concurrent.futures, json
website=Path(__file__).resolve().parents[1]
root=website/'assets'
locale_codes={'en-GB':'en-gb','en-AU':'en-au','en-CA':'en-ca','de-DE':'de-de','fr-FR':'fr-fr','fr-CA':'fr-ca','es-ES':'es-es','es-MX':'es-mx','it':'it-it','pt-BR':'pt-br','ja':'ja-jp','ko':'ko-kr','tr':'tr-tr','ru':'ru-ru','uk':'uk-ua','zh-Hans':'zh-cn','zh-Hant':'zh-tw','et':'et-ee'}
active={item['locale'] for item in json.loads((website/'locales/manifest.json').read_text())}
locale_codes={locale:code for locale,code in locale_codes.items() if locale in active}
def fetch(item):
 locale,code=item
 data=urllib.request.urlopen('https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/'+code+'?size=250x83',timeout=30).read()
 assert b'<svg' in data and len(data)>1000,locale
 path=root/locale;path.mkdir(exist_ok=True);(path/'app-store-badge.svg').write_bytes(data)
 return locale
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 for locale in pool.map(fetch,locale_codes.items()):print('Official badge: '+locale,flush=True)
