import json
import sys


def check(targets):
    errors = []
    if not targets:
        return ["No Release build settings were provided"]
    for target in targets:
        settings = target["buildSettings"]
        if settings.get("CODE_SIGNING_ALLOWED") == "NO":
            continue
        if settings.get("CODE_SIGN_IDENTITY") == "Apple Distribution":
            if settings.get("CODE_SIGN_STYLE") != "Manual":
                errors.append(
                    f'{target["target"]}: Apple Distribution requires manual Release signing'
                )
    return errors


if __name__ == "__main__":
    errors = check(json.load(sys.stdin))
    if errors:
        for error in errors:
            print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
    print("Release signing settings are consistent")
