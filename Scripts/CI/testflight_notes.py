import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


MAX_CHARACTERS = 4000
RECENT_COMMITS = 50
GENERAL_CHECK = "Convert an amount, switch currencies, and refresh rates; check the result and layout."
LEGACY_NOTES = (
    "This build predates commit-based testing notes; its change list is unavailable.\n\n"
    "What to test\n- " + GENERAL_CHECK + "\n"
    "- Add a Home Screen widget and confirm its currencies and displayed rate.\n"
    "Report unexpected results or layout issues through TestFlight."
)
CHECKS = {
    "widgets": "Add and edit a Home Screen widget, change its currency pair, and confirm its rate and layout.",
    "history": "Open rate history, change the period and currency pair, and check the chart and selected period.",
    "onboarding": "On a fresh install, complete onboarding; reopen the app and check that your choices persist.",
    "search": "Search for a currency by name or code, select it, and confirm the conversion uses that currency.",
    "intents": "Run a Siri conversion and open a currency from Spotlight; confirm the amount and currency pair.",
    "refresh": "Refresh rates, reopen the app, and check the updated values and any offline or error state.",
    "appearance": "Check the changed screen in light and dark appearance and with a larger text size.",
    "home": "Enter and edit an amount, switch the currency pair, and check the conversion and keypad.",
}


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def git(*args):
    return command("git", *args)


def api(*args):
    return json.loads(command("gh", "api", *args))


def is_ancestor(base, head):
    if not re.fullmatch(r"[0-9a-f]{40}", base):
        return False
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", base, head],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def previous_release(head, repository, current_run):
    page = 1
    while True:
        runs = api("--method", "GET", f"repos/{repository}/actions/workflows/publish.yml/runs",
                   "-f", "branch=main", "-f", "status=success", "-f", "event=workflow_run",
                   "-F", "per_page=100", "-F", f"page={page}")["workflow_runs"]
        if not runs:
            return None, "No previous published commit is available."
        for run in runs:
            if str(run["id"]) == str(current_run):
                continue
            pages = api(f"repos/{repository}/actions/runs/{run['id']}/artifacts",
                        "--paginate", "--slurp")
            artifacts = [artifact for result in pages for artifact in result["artifacts"]]
            if not any(item["name"] == "currency-release-build" and not item["expired"]
                       for item in artifacts):
                continue
            with tempfile.TemporaryDirectory() as directory:
                subprocess.run(["gh", "run", "download", str(run["id"]), "--repo", repository,
                                "--name", "currency-release-build", "--dir", directory], check=True)
                commit_file = Path(directory) / "CurrencyCommit.txt"
                if not commit_file.is_file():
                    return None, "The previous release artifact predates commit recording."
                base = commit_file.read_text().strip()
            if not is_ancestor(base, head):
                return None, "The previous published commit is unavailable or is not an ancestor of this build."
            return base, None
        page += 1


def user_facing(path):
    parts = Path(path).parts
    if not parts or parts[0] not in {"App", "Features", "Domain", "DesignSystem", "Infrastructure"}:
        return False
    if Path(path).suffix.lower() in {".md", ".rst"}:
        return False
    if "Sources" in parts or "Resources" in parts:
        return True
    return parts[0] == "App" and Path(path).suffix in {".entitlements", ".plist", ".xcprivacy"}


def checks_for(paths, subject):
    context = (" ".join(paths) + " " + subject).lower()
    matches = []
    for category in CHECKS:
        tokens = {"intents": ("intent", "siri", "spotlight"),
                  "appearance": ("designsystem", "appearance", "layout", "theme"),
                  "refresh": ("refresh", "exchangerates", "rateprovider")}.get(category, (category,))
        if any(token in context for token in tokens):
            matches.append(CHECKS[category])
    return matches or [GENERAL_CHECK]


def generate_notes(head, base=None, fallback=None):
    if base is not None and not is_ancestor(base, head):
        raise ValueError("The release baseline must be an ancestor of the tested commit.")
    revisions = git("log", "--first-parent", "--format=%H", *([] if base else [f"-{RECENT_COMMITS}"]),
                    f"{base}..{head}" if base else head).splitlines()
    entries = []
    checks = []
    for revision in revisions:
        parents = git("rev-list", "--parents", "-n", "1", revision).split()
        paths = (git("diff", "--name-only", "--no-renames", parents[1], revision)
                 if len(parents) > 1 else
                 git("diff-tree", "--root", "--no-commit-id", "--name-only", "-r", revision)).splitlines()
        visible_paths = [path for path in paths if user_facing(path)]
        if not visible_paths:
            continue
        subject = git("show", "-s", "--format=%s", revision)
        subject = " ".join(subject.split())
        entries.append(f"- {subject[:240]} ({revision[:7]})")
        for check in checks_for(visible_paths, subject):
            if check not in checks:
                checks.append(check)
    provenance = (f"Changes since the previous published build ({base[:7]}), through {head[:7]}."
                  if base else f"Recent changes through {head[:7]} (up to {RECENT_COMMITS} commits; release baseline unavailable).\n{fallback or 'No previous published commit is available.'}")
    if not entries:
        changes = "No user-facing changes were identified in this range."
        checks = [GENERAL_CHECK]
    else:
        changes = "\n".join(entries)
    footer = "\n\nWhat to test\n" + "\n".join("- " + check for check in checks)
    footer += "\nReport unexpected results through TestFlight, including steps to reproduce."
    prefix = provenance + "\n\n"
    kept = list(entries)
    while len(prefix + changes + footer) > MAX_CHARACTERS and kept:
        kept.pop()
        changes = "\n".join(kept) + f"\n- {len(entries) - len(kept)} more user-facing commits omitted to fit TestFlight."
    notes = prefix + changes + footer
    if len(notes) > MAX_CHARACTERS:
        raise ValueError("Testing notes exceed the TestFlight character limit.")
    return notes


def read_notes(path):
    notes = Path(path).read_text().strip() if Path(path).is_file() else LEGACY_NOTES
    if not notes or len(notes) > MAX_CHARACTERS or "\0" in notes:
        raise ValueError("Testing notes must contain 1 to 4000 characters without NUL bytes.")
    return notes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--read", type=Path)
    args = parser.parse_args()
    if args.read is not None:
        print(read_notes(args.read))
        return
    if args.output_dir is None:
        parser.error("--output-dir is required when generating notes")
    head = git("rev-parse", "HEAD")
    base, fallback = previous_release(head, os.environ["GH_REPO"], os.environ["GITHUB_RUN_ID"])
    notes = generate_notes(head, base, fallback)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "CurrencyCommit.txt").write_text(head + "\n")
    (args.output_dir / "CurrencyTestNotes.txt").write_text(notes + "\n")
    print(notes)


if __name__ == "__main__":
    main()
