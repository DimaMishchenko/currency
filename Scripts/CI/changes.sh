#!/bin/bash
set -euo pipefail

xcode=false
publish=false
base=${1:-}
files=$(mktemp)
trap 'rm -f "$files"' EXIT

if [[ -z "$base" || "$base" =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  xcode=true
  publish=true
else
  git diff --no-renames --name-only -z "$base" HEAD > "$files"
  while IFS= read -r -d '' file; do
    if [[ "$file" =~ ^(App|DesignSystem|Domain/[^/]+|Features/[^/]+|App/Modules/[^/]+|Apps/[^/]+|Apps/[^/]+/App|Apps/[^/]+/Modules/[^/]+|AppExtensions/[^/]+|Foundation/[^/]+)/README\.md$ ]]; then
      continue
    fi
    if [[ "$file" =~ ^(App/Tests/|App/Modules/[^/]+/Tests/|Apps/[^/]+/Tests/|Apps/[^/]+/Modules/[^/]+/Tests/|AppExtensions/[^/]+/Tests/|Foundation/[^/]+/Tests/|(DesignSystem|Domain/[^/]+|Features/[^/]+)/Tests/|(Domain/[^/]+|Features/[^/]+)/HarnessApp/) ]]; then
      xcode=true
      continue
    fi
    case "$file" in
      Documentation/*|README.md|LICENSE|.gitignore)
        ;;
      Tools/SimulatorWidgets/*|.swift-format|.github/workflows/tests.yml)
        xcode=true ;;
      Scripts/CI/testflight_notes.py)
        publish=true ;;
      .github/workflows/publish.yml|Scripts/CI/signing.sh|Scripts/CI/release.sh|Scripts/CI/verify_ipa.sh)
        xcode=true; publish=true ;;
      .github/*|Scripts/CI/*)
        ;;
      *) xcode=true; publish=true ;;
    esac
  done < "$files"
fi

printf 'xcode=%s\npublish=%s\n' "$xcode" "$publish" >> "$GITHUB_OUTPUT"
printf '%s\n' "$publish" > "$RUNNER_TEMP/ShouldPublish.txt"
printf 'Simulator tests: %s; TestFlight upload: %s\n' "$xcode" "$publish" >> "$GITHUB_STEP_SUMMARY"
