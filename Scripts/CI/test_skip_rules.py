"""Exercise skip decisions against real Git diffs and mocked release history."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent


class SkipRulesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.output = self.root / "output"
        self.summary = self.root / "summary"
        self.env = dict(os.environ, GITHUB_OUTPUT=str(self.output),
                        GITHUB_STEP_SUMMARY=str(self.summary), RUNNER_TEMP=str(self.root))
        self.git("init", "-q")
        self.git("config", "user.name", "CI Tests")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("commit", "--allow-empty", "-qm", "base")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True).strip()

    def commit_file(self, name):
        file = self.repo / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("changed\n")
        self.git("add", "--", name)
        self.git("commit", "-qm", "change")

    def classify(self, base):
        self.output.write_text("")
        subprocess.run(["bash", str(SCRIPTS / "changes.sh"), base],
                       cwd=self.repo, env=self.env, check=True)
        return self.output.read_text()

    def test_path_categories(self):
        cases = {
            "Documentation/TODO.md": (False, False),
            "README.md": (False, False),
            "Domain/ExchangeRates/README.md": (False, False),
            "App/Modules/CurrencyApplication/README.md": (False, False),
            ".swift-format": (False, False),
            ".github/ISSUE_TEMPLATE/bug.yml": (False, False),
            ".github/workflows/public-beta.yml": (False, False),
            "Scripts/CI/public_beta.sh": (False, False),
            "App/Tests/Integration.swift": (True, False),
            "App/Modules/CurrencyApplication/Tests/Test.swift": (True, False),
            "DesignSystem/Tests/Test.swift": (True, False),
            "Domain/ExchangeRates/Tests/Test.swift": (True, False),
            "Features/Home/HarnessApp/App.swift": (True, False),
            ".github/workflows/tests.yml": (True, False),
            "App/Sources/App.swift": (True, True),
            "App/Resources/README.md": (True, True),
            "Domain/ExchangeRates/Sources/Resources/README.md": (True, True),
            "Features/Home/Sources/Tests/Helper.swift": (True, True),
            "App/Widgets/Resources/icon.png": (True, True),
            "App/Configuration/Currency.entitlements": (True, True),
            "Features/Home/Package.swift": (True, True),
            "Project.swift": (True, True),
            "Tuist.swift": (True, True),
            "Package.swift": (True, True),
            ".github/workflows/publish.yml": (True, True),
            "Scripts/CI/signing.sh": (True, True),
            "Scripts/CI/release.sh": (True, True),
            "Scripts/CI/verify_ipa.sh": (True, True),
            "new-folder/unknown\nfile": (True, True),
        }
        for name, (xcode, publish) in cases.items():
            with self.subTest(path=name):
                base = self.git("rev-parse", "HEAD")
                self.commit_file(name)
                self.assertEqual(self.classify(base),
                                 f"xcode={str(xcode).lower()}\npublish={str(publish).lower()}\n")
                self.assertEqual((self.root / "ShouldPublish.txt").read_text(),
                                 f"{str(publish).lower()}\n")

    def test_whole_push_and_both_sides_of_rename(self):
        base = self.git("rev-parse", "HEAD")
        self.commit_file("App/Sources/App.swift")
        self.commit_file("Documentation/TODO.md")
        self.assertEqual(self.classify(base), "xcode=true\npublish=true\n")
        base = self.git("rev-parse", "HEAD")
        self.git("mv", "App/Sources/App.swift", "Documentation/Removed.swift")
        self.git("commit", "-qm", "rename")
        self.assertEqual(self.classify(base), "xcode=true\npublish=true\n")

    def test_missing_history_and_empty_diff(self):
        for base in ("", "0" * 40, "f" * 40):
            with self.subTest(base=base):
                self.assertEqual(self.classify(base), "xcode=true\npublish=true\n")
        self.assertEqual(self.classify("HEAD"), "xcode=false\npublish=false\n")


class ReleaseResolutionTests(unittest.TestCase):
    def resolve(self, scenario, run_id=""):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            output = root / "output"
            output.touch()
            mock = root / "gh"
            mock.write_text("""#!/bin/bash
set -euo pipefail
if [[ "$SCENARIO" == error ]]; then exit 1; fi
if [[ "$*" == *'/artifacts'* ]]; then
  if [[ "$*" == *'/runs/98/'* && "$SCENARIO" != empty ]]; then
    echo true
  else
    echo false
  fi
elif [[ "$SCENARIO" == paginated ]]; then
  case "$*" in
    *' page=1 '*) echo 100 ;;
    *' page=2 '*) echo 98 ;;
  esac
elif [[ "$SCENARIO" != empty ]]; then
  printf '100\\n99\\n98\\n'
fi
""")
            mock.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       SCENARIO=scenario, RELEASE_RUN_ID=run_id, GH_REPO="owner/repo",
                       GITHUB_OUTPUT=str(output), GITHUB_STEP_SUMMARY=str(root / "summary"))
            result = subprocess.run(["bash", str(SCRIPTS / "resolve_release.sh")],
                                    env=env, capture_output=True, text=True, timeout=10)
            return result.returncode, output.read_text()

    def test_scheduled_retry_skips_noop_and_expired_runs(self):
        self.assertEqual(self.resolve("history"), (0, "run_id=98\n"))
        self.assertEqual(self.resolve("paginated"), (0, "run_id=98\n"))

    def test_event_uses_only_its_own_artifact(self):
        self.assertEqual(self.resolve("history", "100"), (0, ""))
        self.assertEqual(self.resolve("history", "98"), (0, "run_id=98\n"))

    def test_no_release_and_api_failure(self):
        self.assertEqual(self.resolve("empty"), (0, ""))
        self.assertEqual(self.resolve("error"), (1, ""))


if __name__ == "__main__":
    unittest.main()
