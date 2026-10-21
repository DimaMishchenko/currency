import json
from pathlib import Path
import unittest


class ApprovedMetadataTests(unittest.TestCase):
    def test_store_field_limits_and_contexts(self):
        metadata = json.loads((Path(__file__).resolve().parents[1] / 'metadata.json').read_text())
        self.assertEqual(len(metadata['locales']), 18)
        self.assertEqual(set(metadata['families']), {'default', 'offline', 'travel', 'history', 'crypto', 'metals'})
        for locale, copy in metadata['locales'].items():
            with self.subTest(locale=locale):
                for field, limit in [('name', 30), ('subtitle', 30), ('description', 4000), ('promotionalText', 170)]:
                    self.assertTrue(copy[field].strip())
                    self.assertLessEqual(len(copy[field]), limit)
                self.assertLessEqual(len(copy['keywords'].encode('utf-8')), 100)
                self.assertEqual(set(copy['contextualPromotionalText']), set(metadata['families']) - {'default'})
                self.assertTrue(all(0 < len(x) <= 170 for x in copy['contextualPromotionalText'].values()))
                self.assertNotIn('free forever', copy['description'].lower())


if __name__ == '__main__':
    unittest.main()
