import copy
import json
from pathlib import Path
import tempfile
import unittest

from check_localizations import LANGUAGES, check


class PluralCatalogTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.catalog = self.root / "App/Resources/Localizable.xcstrings"
        self.catalog.parent.mkdir(parents=True)
        self.entry = {
            "localizations": {
                language: {"stringUnit": {"state": "translated", "value": "%lld results"}}
                for language in LANGUAGES
            }
        }
        self.entry["localizations"]["ru"] = {
            "variations": {
                "plural": {
                    category: {"stringUnit": {"state": "translated", "value": "%lld результатов"}}
                    for category in ("one", "few", "many", "other")
                }
            }
        }

    def failures(self, entry):
        self.catalog.write_text(json.dumps({"sourceLanguage": "en", "strings": {"results": entry}}))
        return check(self.root)[2]

    def test_accepts_complete_plural_catalog(self):
        self.assertEqual(self.failures(self.entry), [])

    def test_checks_every_plural_branch(self):
        for category in ("one", "few", "many", "other"):
            for field, invalid, expected in (
                ("value", "%@ результатов", "placeholders differ"),
                ("value", "%lld\nрезультатов", "line breaks differ"),
                ("value", "", "unfinished translation"),
                ("state", "new", "unfinished translation"),
            ):
                with self.subTest(category=category, field=field, invalid=invalid):
                    entry = copy.deepcopy(self.entry)
                    entry["localizations"]["ru"]["variations"]["plural"][category]["stringUnit"][field] = invalid
                    self.assertTrue(any(expected in failure for failure in self.failures(entry)))

    def test_rejects_plural_without_fallback(self):
        del self.entry["localizations"]["ru"]["variations"]["plural"]["other"]
        self.assertTrue(any("Invalid plural categories" in item for item in self.failures(self.entry)))

    def test_rejects_unknown_category(self):
        plural = self.entry["localizations"]["ru"]["variations"]["plural"]
        plural["some"] = plural["few"]
        self.assertTrue(any("Invalid plural categories" in item for item in self.failures(self.entry)))

    def test_preserves_shortcut_phrase_count_check(self):
        self.entry["localizations"] = {
            language: {"stringSet": {"state": "translated", "values": ["Open ${applicationName}"]}}
            for language in LANGUAGES
        }
        self.entry["localizations"]["ru"]["stringSet"]["values"].append("Launch ${applicationName}")
        self.assertTrue(any("phrase count differs" in item for item in self.failures(self.entry)))


if __name__ == "__main__":
    unittest.main()
