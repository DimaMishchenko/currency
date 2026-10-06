import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import zipfile


SCRIPTS = Path(__file__).resolve().parent


class ReleaseConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        plutil = self.tools / "plutil"
        plutil.write_text("#!/bin/sh\nexit 0\n")
        plutil.chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=f"{self.tools}{os.pathsep}{os.environ['PATH']}",
            RUNNER_TEMP=str(self.root),
            APPLE_TEAM_ID="TESTTEAM",
            CURRENCY_BUILD_NUMBER="42",
            CURRENCY_APP_PROFILE_UUID="phone-profile",
            CURRENCY_WIDGET_PROFILE_UUID="phone-widget-profile",
            CURRENCY_WATCH_PROFILE_UUID="watch-profile",
            CURRENCY_WATCH_WIDGET_PROFILE_UUID="watch-widget-profile",
        )

    def test_profile_names_fit_client_limit_for_all_bundles(self):
        bundles = [
            "com.dimasike.currency", "com.dimasike.currency.widgets",
            "com.dimasike.currency.watchkitapp",
            "com.dimasike.currency.watchkitapp.widgets",
            "com.dimasike." + "longbundle" * 20,
        ]
        for bundle in bundles:
            with self.subTest(bundle=bundle):
                names = [subprocess.run(
                    ["bash", str(SCRIPTS / "profile_name.sh"), bundle],
                    check=True, capture_output=True, text=True,
                ).stdout.strip() for _ in range(2)]
                for name in names:
                    self.assertLessEqual(len(name), 64)
                    self.assertRegex(name, r"^Currency CI .+ [0-9]{8} [0-9a-f]{8}$")
                self.assertNotEqual(*names)

    def test_export_includes_every_embedded_bundle_profile(self):
        output = self.root / "ExportOptions.plist"
        subprocess.run(
            ["bash", str(SCRIPTS / "release.sh"), "export-options", str(output)],
            check=True, env=self.env, capture_output=True,
        )
        options = plistlib.loads(output.read_bytes())
        self.assertEqual(options["signingStyle"], "manual")
        self.assertFalse(options["manageAppVersionAndBuildNumber"])
        self.assertEqual(options["provisioningProfiles"], {
            "com.dimasike.currency": "phone-profile",
            "com.dimasike.currency.widgets": "phone-widget-profile",
            "com.dimasike.currency.watchkitapp": "watch-profile",
            "com.dimasike.currency.watchkitapp.widgets": "watch-widget-profile",
        })

    def test_missing_watch_signing_values_fail_before_creating_export(self):
        for name in ("CURRENCY_WATCH_PROFILE_UUID", "CURRENCY_WATCH_WIDGET_PROFILE_UUID"):
            for value in (None, ""):
                with self.subTest(name=name, value=value):
                    env = dict(self.env)
                    if value is None:
                        env.pop(name)
                    else:
                        env[name] = value
                    output = self.root / "Missing.plist"
                    result = subprocess.run(
                        ["bash", str(SCRIPTS / "release.sh"), "export-options", str(output)],
                        env=env, capture_output=True, text=True,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"Missing release value: {name}", result.stderr)
                    self.assertFalse(output.exists())

    def test_ipa_requires_watch_app_and_its_widget_before_signature_validation(self):
        app = "Payload/Currency.app/"
        phone_widget = app + "PlugIns/CurrencyWidgets.appex/"
        watch = app + "Watch/CurrencyWatch.app/"
        for entries in ([app, phone_widget], [app, phone_widget, watch]):
            with self.subTest(entries=entries):
                ipa = self.root / "MissingWatch.ipa"
                with zipfile.ZipFile(ipa, "w") as archive:
                    for entry in entries:
                        archive.writestr(entry, "")
                result = subprocess.run(
                    ["bash", str(SCRIPTS / "verify_ipa.sh"), str(ipa)],
                    env=self.env, capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Missing Watch app or widget extension in IPA", result.stderr)
                self.assertEqual(list(self.root.glob("currency-ipa.*")), [])


if __name__ == "__main__":
    unittest.main()
