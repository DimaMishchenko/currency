#!/bin/bash
set -euo pipefail

case "${1:-}" in
  allocate)
    asc builds next-build-number --app "$ASC_APP_ID" --platform IOS \
      --output json > "$RUNNER_TEMP/currency-build-number.json"
    number=$(jq -er '.nextBuildNumber' "$RUNNER_TEMP/currency-build-number.json")
    echo "CURRENCY_BUILD_NUMBER=$number" >> "$GITHUB_ENV"
    echo "Release build $number"
    ;;
  export-options)
    cat > "$2" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>export</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>$APPLE_TEAM_ID</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>provisioningProfiles</key><dict>
  <key>com.dimasike.currency</key><string>$CURRENCY_APP_PROFILE_UUID</string>
  <key>com.dimasike.currency.widgets</key><string>$CURRENCY_WIDGET_PROFILE_UUID</string>
</dict>
</dict></plist>
EOF
    plutil -lint "$2"
    ;;
  upload)
    result="$RUNNER_TEMP/currency-upload.json"
    if ! asc publish testflight --app "$ASC_APP_ID" --ipa "$2" \
        --upload-only --wait --timeout 60m --output json > "$result"; then
      build_id=$(jq -r '.buildId // empty' "$result")
      if [[ -z "$build_id" ]]; then
        # A timeout may occur after upload but before asc receives the build ID.
        asc builds info --app "$ASC_APP_ID" \
          --build-number "$CURRENCY_BUILD_NUMBER" --platform IOS --output json \
          > "$RUNNER_TEMP/currency-resolved-build.json"
        build_id=$(jq -er '.data.id' "$RUNNER_TEMP/currency-resolved-build.json")
      fi
      asc builds wait --build-id "$build_id" --fail-on-invalid --timeout 60m \
        --output json > "$RUNNER_TEMP/currency-wait.json"
    else
      build_id=$(jq -er '.buildId' "$result")
      jq -e '.processingState == "VALID"' "$result" >/dev/null
    fi
    echo "TestFlight processed build ID $build_id"
    ;;
  *) echo "usage: $0 {allocate|export-options PATH|upload IPA}" >&2; exit 2 ;;
esac
