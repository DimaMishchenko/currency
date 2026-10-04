import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import testflight_notes as notes


SCRIPTS = Path(__file__).resolve().parent


class TestingNotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.original_directory = Path.cwd()
        os.chdir(self.repo)
        self.addCleanup(os.chdir, self.original_directory)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "CI Tests")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("commit", "--allow-empty", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", *args], text=True).strip()

    def commit(self, name, subject):
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(path.read_text() + "changed\n" if path.exists() else "changed\n")
        self.git("add", "--", name)
        self.git("commit", "-qm", subject)
        return self.git("rev-parse", "HEAD")

    def test_changes_checks_and_exact_checkout(self):
        widget = self.commit("App/Widgets/Sources/HistoryWidget.swift", "Fix history period")
        self.commit(".github/workflows/tests.yml", "Change CI")
        self.commit("Tuist/Package.resolved", "Bump dependencies")
        self.commit("Features/Home/Tests/Test.swift", "Change tests")
        head = self.commit("Features/Home/Sources/Home.swift", "Improve keypad")
        self.commit("Features/Onboarding/Sources/Flow.swift", "Future onboarding")
        result = notes.generate_notes(head, self.base)
        self.assertIn(f"Fix history period ({widget[:7]})", result)
        self.assertIn("change the period", result)
        self.assertIn("keypad", result)
        for excluded in ["Change CI", "Bump dependencies", "Change tests", "Future onboarding"]:
            self.assertNotIn(excluded, result)

    def test_migrated_paths_and_historical_rename_notes(self):
        historical = self.commit("App/Widgets/Sources/Widget.swift", "Fix widget refresh")
        target = Path("AppExtensions/CurrencyWidgets/Sources/Widget.swift")
        target.parent.mkdir(parents=True)
        self.git("mv", "App/Widgets/Sources/Widget.swift", str(target))
        self.git("commit", "-qm", "Move widget sources")
        renamed = self.git("rev-parse", "HEAD")
        app = self.commit("Apps/Currency/App/Sources/App.swift", "Improve conversion")
        appearance = self.commit("Foundation/DesignSystem/Sources/Colors.swift", "Adjust theme")
        self.commit("Apps/Currency/Tests/Test.swift", "Update app tests")
        self.commit("AppExtensions/CurrencyWidgets/Tests/WidgetIntegrationTests/Test.swift", "Update widget tests")
        head = self.git("rev-parse", "HEAD")
        result = notes.generate_notes(head, self.base)
        for subject, revision in (("Fix widget refresh", historical), ("Move widget sources", renamed),
                                  ("Improve conversion", app), ("Adjust theme", appearance)):
            self.assertIn(f"{subject} ({revision[:7]})", result)
        self.assertIn(notes.CHECKS["widgets"], result)
        self.assertIn(notes.CHECKS["appearance"], result)
        self.assertNotIn("Update app tests", result)
        self.assertNotIn("Update widget tests", result)

    def test_legacy_and_migrated_production_paths_remain_user_facing(self):
        for path in (
            "App/Sources/App.swift",
            "App/Resources/Localizable.xcstrings",
            "App/Modules/CurrencyApplication/Sources/Application.swift",
            "App/Widgets/Sources/Widget.swift",
            "App/Widgets/Resources/Widget.xcstrings",
            "DesignSystem/Sources/DesignSystem/Colors.swift",
            "Infrastructure/CoordinatedFiles/Sources/CoordinatedFiles/File.swift",
            "Apps/Currency/App/Sources/App.swift",
            "Apps/Currency/App/Resources/Localizable.xcstrings",
            "Apps/Currency/Modules/CurrencyApplication/Sources/Application.swift",
            "AppExtensions/CurrencyWidgets/Sources/Widget.swift",
            "AppExtensions/CurrencyWidgets/Resources/Widget.xcstrings",
            "Foundation/DesignSystem/Sources/DesignSystem/Colors.swift",
            "Foundation/CoordinatedFiles/Sources/CoordinatedFiles/File.swift",
        ):
            with self.subTest(path=path):
                self.assertTrue(notes.user_facing(path))
                self.assertFalse(notes.user_facing(str(Path(path).with_suffix(".md"))))

    def test_app_and_extension_configuration_are_user_facing(self):
        for path in ("Apps/Currency/App/Configuration/Currency.entitlements",
                     "AppExtensions/CurrencyWidgets/Configuration/Currency.entitlements",
                     "App/Configuration/Currency.entitlements"):
            with self.subTest(path=path):
                self.assertTrue(notes.user_facing(path))

    def test_real_gitmoji_subjects_are_safe_and_keep_international_text(self):
        subjects = ["🐛 widgets: preserve history period", "✨ home: add contextual tips",
                    "⚡️ rates: speed up refresh", "🎨 appearance: improve layout",
                    "♻️ conversion: simplify update", "🔧 sélection: corriger Kč € 日本語 العربية हिन्दी"]
        for subject in subjects:
            head = self.commit("Features/Home/Sources/Home.swift", subject)
        result = notes.generate_notes(head, self.base)
        for subject in subjects:
            self.assertIn(subject.split(":", 1)[1].strip(), result)
        self.assertIsNone(notes.REJECTED_CHARACTERS.search(result))
        self.assertNotIn("️", result)
        self.assertIn("sélection", result)

    def test_generation_limits_after_sanitization(self):
        head = self.commit("Features/Home/Sources/Home.swift", "🐛" * 300 + "Fixed conversion")
        result = notes.generate_notes(head, self.base)
        self.assertIn(f"Fixed conversion ({head[:7]})", result)
        self.assertNotIn("🐛", result)

    def test_baseline_excludes_already_published_changes(self):
        published = self.commit("Features/Home/Sources/Home.swift", "Old conversion")
        head = self.commit("Features/Search/Sources/Search.swift", "New currency search")
        result = notes.generate_notes(head, published)
        self.assertNotIn("Old conversion", result)
        self.assertIn("New currency search", result)
        self.assertIn("Search for a currency", result)

    def test_no_user_facing_changes(self):
        head = self.commit("App/Sources/README.md", "Documentation only")
        result = notes.generate_notes(head, self.base)
        self.assertIn("No user-facing changes", result)
        self.assertIn(notes.GENERAL_CHECK, result)
        self.assertNotIn("Documentation only", result)

    def test_recent_history_is_labeled_and_bounded(self):
        for index in range(52):
            self.commit("Features/Home/Sources/Home.swift", f"Change {index:02}")
        result = notes.generate_notes(self.git("rev-parse", "HEAD"), fallback="Legacy artifact.")
        self.assertIn("release baseline unavailable", result)
        self.assertIn("Legacy artifact.", result)
        self.assertNotIn("Change 00 (", result)
        self.assertIn("Change 51 (", result)

    def test_notes_limit_preserves_checks_and_counts_omissions(self):
        for index in range(25):
            self.commit("App/Widgets/Sources/Widget.swift", f"Widget change {index} " + "x" * 230)
        result = notes.generate_notes(self.git("rev-parse", "HEAD"), self.base)
        self.assertLessEqual(len(result), 4000)
        self.assertIn("omitted to fit TestFlight", result)
        self.assertIn("Add and edit a Home Screen widget", result)
        self.assertIn("Widget change 24", result)

    def test_merge_uses_only_changes_against_first_parent(self):
        self.git("checkout", "-qb", "ci-branch")
        self.commit(".github/workflows/tests.yml", "Branch CI change")
        self.git("checkout", "-q", "main")
        published = self.commit("Features/Home/Sources/Home.swift", "Already published app change")
        self.git("merge", "--no-ff", "-qm", "Merge CI only", "ci-branch")
        result = notes.generate_notes(self.git("rev-parse", "HEAD"), published)
        self.assertNotIn("Merge CI only", result)
        self.assertNotIn("Already published app change", result)
        self.assertIn("No user-facing changes", result)

    def test_nonancestor_baseline_rejected(self):
        self.git("checkout", "-qb", "other")
        other = self.commit("Features/Home/Sources/Home.swift", "Other branch")
        self.git("checkout", "-q", "main")
        with self.assertRaises(ValueError):
            notes.generate_notes(self.base, other)

    def configure_gh(self, runs, artifacts, commits):
        fixture = self.root / "fixtures.json"
        fixture.write_text(json.dumps({"runs": runs, "artifacts": artifacts, "commits": commits}))
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
fixture = json.loads(Path(os.environ["GH_FIXTURE"]).read_text())
args = sys.argv[1:]
if args[:2] == ["run", "download"]:
    directory = Path(args[args.index("--dir") + 1])
    commit = fixture["commits"].get(args[2])
    if commit is not None:
        (directory / "CurrencyCommit.txt").write_text(commit)
elif args[0] == "api":
    endpoint = next(value for value in args if value.startswith("repos/"))
    if endpoint.endswith("/runs"):
        page = next(value for value in args if value.startswith("page="))
        print(json.dumps({"workflow_runs": fixture["runs"] if page == "page=1" else []}))
    else:
        run_id = endpoint.split("/")[-2]
        print(json.dumps([{"artifacts": fixture["artifacts"].get(run_id, [])}]))
else:
    sys.exit(2)
''')
        gh.chmod(0o755)
        environment = {"PATH": str(binary) + os.pathsep + os.environ["PATH"], "GH_FIXTURE": str(fixture)}
        context = patch.dict(os.environ, environment)
        context.start()
        self.addCleanup(context.stop)

    def test_release_selection_skips_current_noop_and_expired_artifacts(self):
        head = self.commit("Features/Home/Sources/Home.swift", "Current change")
        artifact = {"name": "currency-release-build", "expired": False}
        self.configure_gh([{"id": value} for value in [9, 8, 7, 6]],
                          {"9": [artifact], "8": [], "7": [dict(artifact, expired=True)], "6": [artifact]},
                          {"9": head, "6": self.base})
        self.assertEqual(notes.previous_release(head, "owner/repo", "9"), (self.base, None))

    def test_legacy_artifact_uses_fallback_even_when_older_commit_exists(self):
        artifact = {"name": "currency-release-build", "expired": False}
        self.configure_gh([{"id": 8, "head_sha": self.base}, {"id": 7}],
                          {"8": [artifact], "7": [artifact]}, {"7": self.base})
        base, fallback = notes.previous_release(self.base, "owner/repo", "9")
        self.assertIsNone(base)
        self.assertIn("predates commit recording", fallback)

    def test_invalid_previous_commit_uses_labeled_fallback(self):
        artifact = {"name": "currency-release-build", "expired": False}
        self.configure_gh([{"id": 8}], {"8": [artifact]}, {"8": "bad SHA"})
        base, fallback = notes.previous_release(self.base, "owner/repo", "9")
        self.assertIsNone(base)
        self.assertIn("not an ancestor", fallback)

    def test_no_previous_release(self):
        self.configure_gh([], {}, {})
        base, fallback = notes.previous_release(self.base, "owner/repo", "9")
        self.assertIsNone(base)
        self.assertIn("No previous published commit", fallback)

    def test_artifact_boundary_normalizes_unicode_before_length_validation(self):
        path = self.root / "CurrencyTestNotes.txt"
        text = "Cafe\u0301 Kč € 日本語 العربية हिन्दी ไทย שָׁלוֹם → ① ◇"
        path.write_text("🐛✨⚡️🎨♻️\ue000\U000f0000\ufffd" + text + " <x\u0301")
        self.assertEqual(notes.read_notes(path), "Café Kč € 日本語 العربية हिन्दी ไทย שָׁלוֹם → ① ◇ x")
        path.write_text("🐛" * 4001 + "a" * 4000)
        self.assertEqual(notes.read_notes(path), "a" * 4000)
        path.write_text("🐛\ue000\ufe0f")
        with self.assertRaises(ValueError):
            notes.read_notes(path)

    def test_rejected_range_edges_match_asc_contract(self):
        for start, end in [(0x20D0, 0x20FF), (0x2400, 0x245F), (0x2500, 0x259F),
                           (0x2600, 0x27EF), (0x2800, 0x28FF), (0x2980, 0x2BFF),
                           (0xE000, 0xF8FF), (0xFE00, 0xFE0F), (0xFFFD, 0xFFFD),
                           (0x10000, 0x10FFFF)]:
            with self.subTest(start=start, end=end):
                self.assertEqual(notes.sanitize_notes("Text" + chr(start) + chr(end)), "Text")

    def test_immutable_notes_and_legacy_promotion_fallback(self):
        path = self.root / "CurrencyTestNotes.txt"
        path.write_text("Published build notes\n")
        self.assertEqual(notes.read_notes(path), "Published build notes")
        path.unlink()
        self.assertIn("predates commit-based", notes.read_notes(path))
        for invalid in ["", "a" * 4001, "nul\0text"]:
            path.write_text(invalid)
            with self.assertRaises(ValueError):
                notes.read_notes(path)



class ReleaseUploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        binary = self.root / "bin"
        binary.mkdir()
        asc = binary / "asc"
        asc.write_text(r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with Path(os.environ["ASC_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\n")
if args[:2] == ["publish", "testflight"]:
    print(json.dumps({"buildId": "build-42", "processingState": os.environ.get("UPLOAD_STATE", "VALID")}))
    sys.exit(int(os.environ.get("UPLOAD_EXIT", "0")))
if args[:3] == ["builds", "test-notes", "create"]:
    value = args[args.index("--whats-new") + 1]
    refused = [(0x20D0, 0x20FF), (0x2400, 0x245F), (0x2500, 0x259F), (0x2600, 0x27EF),
               (0x2800, 0x28FF), (0x2980, 0x2BFF), (0xE000, 0xF8FF), (0xFE00, 0xFE0F),
               (0xFFFD, 0xFFFD), (0x10000, 0x10FFFF)]
    if any(start <= ord(character) <= end for character in value for start, end in refused):
        print("What to Test notes contain rejected characters", file=sys.stderr)
        sys.exit(2)
    sys.exit(int(os.environ.get("NOTES_EXIT", "0")))
if args[:2] == ["builds", "wait"]:
    sys.exit(int(os.environ.get("WAIT_EXIT", "0")))
sys.exit(2)
''')
        asc.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                                RUNNER_TEMP=str(self.root), GITHUB_OUTPUT=str(self.root / "output"),
                                ASC_LOG=str(self.root / "asc.log"), ASC_APP_ID="app-42")
        self.text = "Published change (abc1234)\n\nWhat to test\n- Check this exact change."
        (self.root / "CurrencyTestNotes.txt").write_text(self.text + "\n")

    def upload(self, **environment):
        return subprocess.run(["bash", str(SCRIPTS / "release.sh"), "upload", "Currency.ipa"],
                              cwd=SCRIPTS.parent.parent, env=dict(self.environment, **environment),
                              capture_output=True, text=True)

    def commands(self):
        return [json.loads(line) for line in (self.root / "asc.log").read_text().splitlines()]

    def promotion(self, legacy=False):
        (self.root / "CurrencyBuildId.txt").write_text("build-42\n")
        if legacy:
            (self.root / "CurrencyTestNotes.txt").unlink()
        asc = self.root / "bin" / "asc"
        asc.write_text(r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with Path(os.environ["ASC_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\n")
group = {"id": "group-1", "attributes": {"name": "Public Beta", "isInternalGroup": False,
         "publicLinkEnabled": True, "publicLink": "https://testflight.apple.com/join/example"}}
if args[:3] == ["testflight", "groups", "list"]:
    result = {"complete": True, "groups": [], "data": [group, {"id": "internal", "attributes": {"isInternalGroup": True}}]}
elif args[:2] == ["builds", "info"]:
    result = {"data": {"attributes": {"processingState": "VALID", "expirationDate": "2099-01-01T00:00:00Z"},
              "relationships": {"preReleaseVersion": {"data": {"id": "version-1"}}}},
              "included": [{"id": "version-1", "type": "preReleaseVersions", "attributes": {"version": "1.0"}}]}
elif args[:3] == ["builds", "build-beta-detail", "view"]:
    result = {"data": {"id": "detail-1", "attributes": {"externalBuildState": "READY_FOR_TESTING"}}}
elif args[:3] == ["testflight", "app-localizations", "list"]:
    result = {"data": [{"attributes": {"description": "Currency", "feedbackEmail": "feedback@example.invalid"}}]}
elif args[:3] == ["testflight", "review", "view"]:
    result = {"data": [{"attributes": {key: "present" for key in ["contactFirstName", "contactLastName", "contactEmail", "contactPhone"]}}]}
elif args[:2] == ["publish", "testflight"]:
    result = {}
else:
    print("Unhandled fake ASC command", args, file=sys.stderr)
    sys.exit(2)
print(json.dumps(result))
''')
        environment = dict(self.environment, ASC_KEY_ID="fake", ASC_ISSUER_ID="fake",
                           ASC_PRIVATE_KEY_B64="fake", GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        result = subprocess.run(["bash", str(SCRIPTS / "public_beta.sh"), str(self.root / "CurrencyBuildId.txt")],
                                cwd=SCRIPTS.parent.parent, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        publish = next(args for args in self.commands() if args[:2] == ["publish", "testflight"])
        return publish[publish.index("--test-notes") + 1]

    def test_public_beta_uses_downloaded_notes_without_regenerating(self):
        self.assertEqual(self.promotion(), self.text)

    def test_legacy_public_beta_has_explicit_safe_fallback(self):
        self.assertEqual(self.promotion(legacy=True), notes.LEGACY_NOTES)

    def test_generated_gitmoji_notes_upload_successfully(self):
        repository = self.root / "git"
        repository.mkdir()
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=repository, text=True).strip()
        git("init", "-q", "-b", "main")
        git("config", "user.name", "CI Tests")
        git("config", "user.email", "ci@example.invalid")
        git("commit", "--allow-empty", "-qm", "base")
        base = git("rev-parse", "HEAD")
        source = repository / "Features/Home/Sources/Home.swift"
        source.parent.mkdir(parents=True)
        source.write_text("changed")
        git("add", ".")
        git("commit", "-qm", "🐛 home: fix conversion for Kč € 日本語")
        head = git("rev-parse", "HEAD")
        original_directory = Path.cwd()
        try:
            os.chdir(repository)
            generated = notes.generate_notes(head, base)
        finally:
            os.chdir(original_directory)
        (self.root / "CurrencyTestNotes.txt").write_text(generated)
        result = self.upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        command = self.commands()[1]
        submitted = command[command.index("--whats-new") + 1]
        self.assertEqual(submitted, generated)
        self.assertIn(f"home: fix conversion for Kč € 日本語 ({head[:7]})", submitted)

    def test_upload_sanitizes_previous_unsafe_artifact(self):
        (self.root / "CurrencyTestNotes.txt").write_text("🐛✨⚡️🎨♻️ " + self.text + "\ue000")
        result = self.upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        command = self.commands()[1]
        self.assertEqual(command[command.index("--whats-new") + 1], self.text)

    def test_fake_asc_rejects_unsafe_notes(self):
        result = subprocess.run([str(self.root / "bin" / "asc"), "builds", "test-notes", "create",
                                 "--whats-new", "🐛 Unsafe notes"], env=self.environment,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("rejected characters", result.stderr)

    def test_valid_build_gets_immutable_notes(self):
        result = self.upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        self.assertEqual(commands[1][:3], ["builds", "test-notes", "create"])
        self.assertEqual(commands[1][commands[1].index("--whats-new") + 1], self.text)
        self.assertEqual((self.root / "CurrencyBuildId.txt").read_text(), "build-42\n")
        self.assertEqual((self.root / "output").read_text(), "processed=true\n")

    def test_timeout_recovery_waits_before_setting_notes(self):
        result = self.upload(UPLOAD_EXIT="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([args[:2] for args in self.commands()],
                         [["publish", "testflight"], ["builds", "wait"], ["builds", "test-notes"]])

    def test_invalid_build_never_gets_notes(self):
        result = self.upload(UPLOAD_STATE="INVALID")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.commands()), 1)
        self.assertFalse((self.root / "CurrencyBuildId.txt").exists())

    def test_notes_failure_preserves_processed_build_artifact(self):
        result = self.upload(NOTES_EXIT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "CurrencyBuildId.txt").exists())
        self.assertEqual((self.root / "output").read_text(), "processed=true\n")


if __name__ == "__main__":
    unittest.main()
