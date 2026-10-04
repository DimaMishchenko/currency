import copy
import json
from pathlib import Path
import tempfile
import unittest

from check_localizations import LANGUAGES, check, check_strings_data, resource_directory


class PluralCatalogTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.catalog = self.root / "Apps/Currency/App/Resources/Localizable.xcstrings"
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


class MigratedResourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()

    def test_catalog_coverage_includes_all_production_roots(self):
        catalogs = (
            "Apps/Currency/App/Resources/App.xcstrings",
            "AppExtensions/CurrencyWidgets/Resources/Widgets.xcstrings",
            "Features/Home/Sources/Home/Resources/Home.xcstrings",
            "Domain/Widgets/Sources/Widgets/Resources/Widgets.xcstrings",
            "Foundation/DesignSystem/Sources/DesignSystem/Resources/DesignSystem.xcstrings",
        )
        for name in catalogs:
            path = self.root / name
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({"sourceLanguage": "en", "strings": {}}))
        self.assertEqual(check(self.root), (0, len(catalogs), []))

    def test_compiler_strings_map_to_migrated_resource_owners(self):
        owners = {
            "Apps/Currency/App/Sources/App.swift": "Apps/Currency/App/Resources",
            "AppExtensions/CurrencyWidgets/Sources/Widget.swift": "AppExtensions/CurrencyWidgets/Resources",
            "Features/Home/Sources/Home/View.swift": "Features/Home/Sources/Home/Resources",
            "Domain/Widgets/Sources/Widgets/Widget.swift": "Domain/Widgets/Sources/Widgets/Resources",
        }
        derived = self.root / "DerivedData"
        derived.mkdir()
        for index, (source, resources) in enumerate(owners.items()):
            with self.subTest(source=source):
                self.assertEqual(resource_directory(self.root, self.root / source), self.root / resources)
            catalog = self.root / resources / "Localizable.xcstrings"
            catalog.parent.mkdir(parents=True)
            catalog.write_text(json.dumps({"strings": {"Hello": {}}}))
            (derived / f"{index}.stringsdata").write_text(json.dumps({
                "source": source, "tables": {"Localizable": [{"key": "Hello"}]},
            }))
        self.assertEqual(check_strings_data(self.root, derived), (4, 4, 0, []))
        (derived / "0.stringsdata").write_text(json.dumps({
            "source": next(iter(owners)), "tables": {"Localizable": [{"key": "Missing"}]},
        }))
        self.assertIn("missing from Apps/Currency/App/Resources/Localizable.xcstrings",
                      check_strings_data(self.root, derived)[3][0])

    def test_test_and_harness_strings_remain_excluded(self):
        for source in (
            "Apps/Currency/Tests/IntegrationTests/Test.swift",
            "AppExtensions/CurrencyWidgets/Tests/WidgetIntegrationTests/Test.swift",
            "Features/Home/HarnessApp/App.swift",
            "Domain/Widgets/HarnessApp/App.swift",
            "DerivedSources/Generated.swift",
        ):
            with self.subTest(source=source):
                self.assertIsNone(resource_directory(self.root, self.root / source))


if __name__ == "__main__":
    unittest.main()
