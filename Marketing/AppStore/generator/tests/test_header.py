import hashlib
import json
import sys
import tempfile
from pathlib import Path
import unittest


sys.path.insert(0, str(Path(__file__).parents[1]))
from header_validation import background_identity, pixel_source_sha256, validate_entry


class HeaderLocaleTests(unittest.TestCase):
    def test_header_locales_match_screenshot_placements(self):
        design = Path(__file__).parents[2] / 'design'
        configuration = json.loads((design / 'header-locales.json').read_text())
        recipe = json.loads((design / 'recipe.json').read_text())
        locales = {placement['locale'] for placement in recipe['placements']}
        self.assertEqual(set(configuration['locales']), locales)
        for locale, currencies in configuration['locales'].items():
            with self.subTest(locale=locale):
                self.assertEqual(len(currencies), 3)
                self.assertEqual(len(set(currencies)), 3)
                for currency in currencies:
                    self.assertTrue(configuration['glyphs'][currency])
        self.assertEqual(configuration['locales']['de-DE'], ['EUR', 'CHF', 'USD'])
        self.assertEqual(configuration['locales']['zh-Hans'], ['CNY', 'USD', 'HKD'])
        self.assertEqual(configuration['locales']['zh-Hant'], ['TWD', 'USD', 'HKD'])


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
            entry = dict(locale='de-DE', currencies=['EUR','CHF','USD'], renderIdentity=identity, posterSha256=hashlib.sha256(b'poster').hexdigest(), videoSha256=hashlib.sha256(b'video').hexdigest(), videoComplete=True, uniqueInputFrames=900, uniqueDecodedFrames=900)
            manifest = locale / 'manifest.json'
            manifest.write_text(json.dumps(entry))
            self.assertEqual(validate_entry(root, 'de-DE', entry['currencies'], identity, True), entry)
            for changed in [dict(entry, videoComplete=False), {k:v for k,v in entry.items() if k not in {'videoComplete','videoSha256'}}, dict(entry, renderIdentity={'renderer':'old'}), dict(entry, videoSha256='stale')]:
                manifest.write_text(json.dumps(changed))
                with self.assertRaises(ValueError):
                    validate_entry(root, 'de-DE', entry['currencies'], identity, True)
            manifest.write_text(json.dumps(entry))
            (locale / 'header.mp4').write_bytes(b'changed-video')
            with self.assertRaisesRegex(ValueError, 'Stale locale video'):
                validate_entry(root, 'de-DE', entry['currencies'], identity, True)


if __name__ == '__main__':
    unittest.main()
