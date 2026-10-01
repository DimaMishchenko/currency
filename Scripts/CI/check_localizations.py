import argparse
import collections
import json
from pathlib import Path
import re

LANGUAGES = {
    "en", "zh-Hans", "ja", "es", "de", "fr", "pt-BR", "ko", "zh-Hant", "it", "tr", "ru", "uk"
}
PLACEHOLDER = re.compile(r"\$\{[^}]+\}|%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hlLzjtq])?[@diuoxXfFeEgGaAcCsSp%]")


def values(localization):
    if "stringUnit" in localization:
        return [localization["stringUnit"]]
    if "stringSet" in localization:
        group = localization["stringSet"]
        return [{"state": group["state"], "value": value} for value in group["values"]]
    raise ValueError("Unsupported localization shape")


def check(root):
    failures = []
    entries = 0
    catalogs = sorted(path for owner in ("App", "Domain", "Features") for path in (root / owner).rglob("*.xcstrings"))
    for path in catalogs:
        catalog = json.loads(path.read_text())
        if catalog["sourceLanguage"] != "en":
            failures.append(f"{path}: source language must be English")
        for key, entry in catalog["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            entries += 1
            localizations = entry.get("localizations", {})
            if set(localizations) != LANGUAGES:
                failures.append(f"{path}:{key}: languages {sorted(localizations)}")
                continue
            source = values(localizations["en"])
            for language, localization in localizations.items():
                targets = values(localization)
                if len(targets) != len(source):
                    failures.append(f"{path}:{key}:{language}: phrase count differs")
                    continue
                for english, target in zip(source, targets):
                    value = target["value"]
                    if target["state"] != "translated" or not value.strip():
                        failures.append(f"{path}:{key}:{language}: unfinished translation")
                    if collections.Counter(PLACEHOLDER.findall(english["value"])) != collections.Counter(PLACEHOLDER.findall(value)):
                        failures.append(f"{path}:{key}:{language}: placeholders differ")
                    if english["value"].count("\n") != value.count("\n"):
                        failures.append(f"{path}:{key}:{language}: line breaks differ")
    if not catalogs:
        failures.append("No string catalogs found")
    return entries, len(catalogs), failures


def resource_directory(root, source):
    try:
        parts = source.resolve().relative_to(root).parts
    except ValueError:
        return None
    if "Tests" in parts or "HarnessApp" in parts or "DerivedSources" in parts:
        return None
    if parts[:3] == ("App", "Widgets", "Sources"):
        return root / "App/Widgets/Resources"
    if parts[:2] == ("App", "Sources"):
        return root / "App/Resources"
    if len(parts) >= 5 and parts[0] in {"Features", "Domain"} and parts[2] == "Sources":
        return root.joinpath(*parts[:4], "Resources")
    return None


def is_neutral(key):
    return not any(character.isalpha() for character in PLACEHOLDER.sub("", key))


def check_strings_data(root, derived_data):
    root = root.resolve()
    failures = []
    emissions = set()
    sources = set()
    neutral = 0
    catalog_keys = {}
    paths = sorted(derived_data.rglob("*.stringsdata"))
    if not paths:
        failures.append(f"{derived_data}: no compiler strings data found")
    for path in paths:
        data = json.loads(path.read_text())
        source = Path(data["source"])
        if not source.is_absolute():
            source = root / source
        source = source.resolve()
        resources = resource_directory(root, source)
        if resources is None or not data.get("tables"):
            continue
        sources.add(source)
        for table, strings in data["tables"].items():
            catalog_path = resources / f"{table}.xcstrings"
            if catalog_path not in catalog_keys:
                catalog_keys[catalog_path] = (
                    set(json.loads(catalog_path.read_text())["strings"])
                    if catalog_path.is_file() else set()
                )
            for string in strings:
                key = string["key"]
                emission = (source, table, key)
                if emission in emissions:
                    continue
                emissions.add(emission)
                if key in catalog_keys[catalog_path]:
                    continue
                if is_neutral(key):
                    neutral += 1
                    continue
                line = string.get("location", {}).get("startingLine", "?")
                failures.append(
                    f"{source.relative_to(root)}:{line}: {key!r} missing from "
                    f"{catalog_path.relative_to(root)}"
                )
    if paths and not sources:
        failures.append(f"{derived_data}: no production source strings found")
    return len(emissions), len(sources), neutral, failures


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--strings-data", type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    entries, catalogs, failures = check(root)
    print(f"Validated {entries} entries in {catalogs} catalogs for {len(LANGUAGES)} languages")
    if arguments.strings_data is not None:
        emissions, sources, neutral, source_failures = check_strings_data(root, arguments.strings_data)
        failures.extend(source_failures)
        print(f"Audited {emissions} compiler string keys from {sources} production sources; {neutral} neutral strings accepted without a catalog")
    if failures:
        raise SystemExit("\n".join(failures))
