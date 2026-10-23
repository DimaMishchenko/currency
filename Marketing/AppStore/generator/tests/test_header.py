import hashlib
import json
import sys
import tempfile
from pathlib import Path
import unittest
import unicodedata


sys.path.insert(0, str(Path(__file__).parents[1]))
from header_validation import background_identity, pixel_source_sha256, validate_entry, resolve_currencies, currency_reels


class HeaderLocaleTests(unittest.TestCase):
    def test_header_locales_match_screenshot_placements(self):
        design = Path(__file__).parents[2] / 'design'
        configuration = json.loads((design / 'header-locales.json').read_text())
        recipe = json.loads((design / 'recipe.json').read_text())
        locales = {placement['locale'] for placement in recipe['placements']}
        self.assertEqual(set(configuration['locales']), locales)
        self.assertEqual(len(locales), 18)
        for locale in configuration['locales']:
            currencies = resolve_currencies(configuration, locale)
            with self.subTest(locale=locale):
                self.assertEqual(len(currencies), 3)
                self.assertEqual(len(set(currencies)), 3)
                for currency in currencies:
                    glyph = configuration['glyphs'][currency]
                    self.assertEqual(len(glyph), 1)
                    self.assertEqual(unicodedata.category(glyph), 'Sc')
                    self.assertFalse(any(character.isascii() and character.isalpha() for character in glyph))
                glyphs = [configuration['glyphs'][code] for code in currencies]
                self.assertEqual(len(set(glyphs)), 3)
                self.assertTrue(all(set(reel) == set(glyphs) for reel in currency_reels(glyphs)))
        self.assertEqual(resolve_currencies(configuration, 'de-DE'), ['EUR', 'USD', 'GBP'])
        self.assertEqual(resolve_currencies(configuration, 'zh-Hans'), ['CNY', 'USD', 'EUR'])
        self.assertEqual(resolve_currencies(configuration, 'zh-Hant'), ['TWD', 'EUR', 'GBP'])
        self.assertEqual(configuration['locales']['zh-Hans'], ['CNY', 'USD', 'HKD'])
        self.assertEqual(configuration['locales']['zh-Hant'], ['TWD', 'USD', 'HKD'])

    def test_missing_sign_and_dollar_collision_are_skipped(self):
        configuration = {'locales': {'test': ['CHF', 'CAD', 'USD']}, 'glyphs': {'CAD': '$', 'USD': '$', 'EUR': '€', 'GBP': '£'}, 'fallbacks': ['EUR', 'USD', 'GBP']}
        self.assertEqual(resolve_currencies(configuration, 'test'), ['CAD', 'EUR', 'GBP'])
        for unsupported in ['Fr', 'CHF', 'C$', 'A$', 'MX$', 'R$', 'HK$', 'NT$', '?']:
            with self.subTest(unsupported=unsupported):
                configuration['glyphs']['CHF'] = unsupported
                self.assertEqual(resolve_currencies(configuration, 'test'), ['CAD', 'EUR', 'GBP'])
        configuration['fallbacks'] = ['USD']
        with self.assertRaisesRegex(ValueError, 'Three distinct currency signs'):
            resolve_currencies(configuration, 'test')

    def test_background_identity_includes_linked_freetype(self):
        identity = dict(pixelSourceSha256='code', sourceSha256='layout', fontSha256='font', pillow='12', freetype='2.14')
        self.assertNotEqual(background_identity(identity), background_identity(dict(identity, freetype='2.15')))

    def test_pixel_identity_tracks_drawing_without_proof_or_gallery_changes(self):
        source = (Path(__file__).parents[1] / 'header.py').read_text()
        self.assertNotEqual(pixel_source_sha256(source), pixel_source_sha256(source.replace('#acc4e5', '#acc4e6')))
        self.assertEqual(pixel_source_sha256(source), pixel_source_sha256(source.replace('H09 · language editions', 'Review gallery')))

    def test_gallery_rejects_missing_proof_stale_hash_and_changed_renderer(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            locale = root / 'de-DE'
            locale.mkdir()
            (locale / 'poster.png').write_bytes(b'poster')
            (locale / 'header.mp4').write_bytes(b'video')
            identity = {'renderer': 'current'}
            configuration = {'locales': {'de-DE': ['EUR', 'CHF', 'USD']}, 'glyphs': {'EUR': '€', 'USD': '$', 'GBP': '£'}, 'fallbacks': ['EUR', 'USD', 'GBP']}
            glyphs = ['€', '$', '£']
            entry = dict(locale='de-DE', currencies=['EUR','USD','GBP'], glyphs=glyphs, reels=currency_reels(glyphs), renderIdentity=identity, posterSha256=hashlib.sha256(b'poster').hexdigest(), videoSha256=hashlib.sha256(b'video').hexdigest(), videoComplete=True, uniqueInputFrames=900, uniqueDecodedFrames=900)
            manifest = locale / 'manifest.json'
            manifest.write_text(json.dumps(entry))
            self.assertEqual(validate_entry(root, 'de-DE', configuration, identity, True), entry)
            for changed in [dict(entry, currencies=['EUR','CHF','USD']), dict(entry, glyphs=['€','Fr','$']), dict(entry, reels=[['Fr']]*3), dict(entry, videoComplete=False), {k:v for k,v in entry.items() if k not in {'videoComplete','videoSha256'}}, dict(entry, renderIdentity={'renderer':'old'}), dict(entry, videoSha256='stale')]:
                manifest.write_text(json.dumps(changed))
                with self.assertRaises(ValueError):
                    validate_entry(root, 'de-DE', configuration, identity, True)
            manifest.write_text(json.dumps(entry))
            (locale / 'header.mp4').write_bytes(b'changed-video')
            with self.assertRaisesRegex(ValueError, 'Stale locale video'):
                validate_entry(root, 'de-DE', configuration, identity, True)


if __name__ == '__main__':
    unittest.main()
