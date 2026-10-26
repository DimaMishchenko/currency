from html import unescape
from pathlib import Path
import json
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'locales/manifest.json').read_text())
locales = manifest
strings = json.loads((root / 'locales/waitlist.json').read_text())

with tempfile.TemporaryDirectory(prefix='currency-waitlist-') as directory:
    temporary = Path(directory)
    source = temporary / 'Website'
    source.mkdir()
    for name in ['scripts', 'locales', 'index.html', 'support', 'privacy', 'terms', 'waitlist.js', 'waitlist.css', 'launch.json']:
        original = root / name
        if original.is_dir():
            shutil.copytree(original, source / name)
        else:
            shutil.copy2(original, source / name)
    for badge in (root / 'assets').rglob('app-store-badge.svg'):
        target = source / badge.relative_to(root)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(badge, target)
    (temporary / 'Documentation').mkdir()
    for name in ['PrivacyPolicy.md', 'TermsOfUse.md']:
        shutil.copy2(root.parent / 'Documentation' / name, temporary / 'Documentation' / name)
    worker = source / 'waitlist-worker'
    worker.mkdir()
    (worker / 'index.js').write_text('PRIVATE SOURCE MUST NOT BE PUBLISHED')
    output = temporary / 'built'
    command = ['python3', str(source / 'scripts/build.py'), '--output', str(output), '--base-url', 'https://example.org/project/']
    subprocess.run(command, check=True)
    assert not (output / 'waitlist-worker').exists()
    assert not (output / 'launch.json').exists()
    for locale in locales:
        path = locale['path'].strip('/')
        page = (output / path / 'index.html').read_text()
        assert page.count('<dialog ') == 1
        config = json.loads(re.search(r'id="waitlist-config">(.*?)</script>', page)[1])
        assert config['locale'] == locale['locale']
        assert config['strings'] == strings[locale['locale']]
        assert config['language'] == {'zh-Hans': 'zh-cn', 'zh-Hant': 'zh-tw', 'et': 'en'}.get(locale['locale'], locale['locale'].split('-')[0])
        assert 'href="/project/privacy/"' in page
        assert 'src="/project/waitlist.js?v=' in page
        assert 'href="/project/waitlist.css?v=' in page
        assert 'challenges.cloudflare.com' not in page
        assert 'type="checkbox"' not in page
        assert 'waitlist-consent' not in page
        for key in ['title', 'intro', 'email', 'submit', 'privacy', 'close']:
            assert strings[locale['locale']][key] in unescape(page)
        assert 'https://apps.apple.com/app/id6816213577' in page
    config = json.loads((source / 'launch.json').read_text())
    config['prelaunch'] = False
    (source / 'launch.json').write_text(json.dumps(config))
    subprocess.run(command, check=True)
    for page in output.rglob('*.html'):
        assert 'launch-waitlist' not in page.read_text()
        assert 'waitlist-config' not in page.read_text()
        assert 'challenges.cloudflare.com' not in page.read_text()
    assert not (output / 'waitlist.js').exists()
    assert not (output / 'waitlist.css').exists()
print('PASS: waitlist copy in 14 locales, subpath assets/privacy, consent on submission, private source exclusion and release flag')
