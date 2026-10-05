#!/bin/bash
set -euo pipefail

check_bundle() {
  local bundle=$1 expected_id=$2 expected_profile=$3
  local info=$bundle/Info.plist
  [[ $(plutil -extract CFBundleIdentifier raw -o - "$info") == "$expected_id" ]] \
    || { echo "Wrong bundle ID: $bundle" >&2; exit 1; }
  [[ $(plutil -extract CFBundleVersion raw -o - "$info") == "$CURRENCY_BUILD_NUMBER" ]] \
    || { echo "Wrong build number: $bundle" >&2; exit 1; }
  [[ $(plutil -extract CFBundleShortVersionString raw -o - "$info") == "$app_version" ]] \
    || { echo "Mismatched marketing version: $bundle" >&2; exit 1; }
  security cms -D -i "$bundle/embedded.mobileprovision" > "$workdir/embedded.plist"
  [[ $(plutil -extract UUID raw -o - "$workdir/embedded.plist") == "$expected_profile" ]] \
    || { echo "Wrong provisioning profile: $bundle" >&2; exit 1; }
  codesign --verify --strict "$bundle"
  codesign -d --entitlements :- "$bundle" > "$workdir/signed-entitlements.plist" 2>/dev/null
  [[ $(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$workdir/signed-entitlements.plist") == "$APPLE_TEAM_ID.$expected_id" ]] \
    || { echo "Wrong signed app identifier: $bundle" >&2; exit 1; }
  /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' \
    "$workdir/signed-entitlements.plist" | grep -Fqx '    group.com.dimasike.currency.shared' \
    || { echo "Missing signed App Group: $bundle" >&2; exit 1; }
}

workdir=$(mktemp -d "$RUNNER_TEMP/currency-ipa.XXXXXX")
trap 'verify_status=$?; rm -rf "$workdir"; exit "$verify_status"' EXIT
unzip -q "$1" -d "$workdir"
app=$workdir/Payload/Currency.app
widget=$app/PlugIns/CurrencyWidgets.appex
[[ -d "$app" && -d "$widget" ]] || { echo 'Missing app or widget extension in IPA' >&2; exit 1; }
watch=$app/Watch/CurrencyWatch.app
watch_widget=$watch/PlugIns/CurrencyWatchWidgets.appex
[[ -d "$watch" && -d "$watch_widget" ]] || { echo 'Missing Watch app or widget extension in IPA' >&2; exit 1; }
app_version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Info.plist")
check_bundle "$app" com.dimasike.currency "$CURRENCY_APP_PROFILE_UUID"
check_bundle "$widget" com.dimasike.currency.widgets "$CURRENCY_WIDGET_PROFILE_UUID"
check_bundle "$watch" com.dimasike.currency.watchkitapp "$CURRENCY_WATCH_PROFILE_UUID"
check_bundle "$watch_widget" com.dimasike.currency.watchkitapp.widgets "$CURRENCY_WATCH_WIDGET_PROFILE_UUID"
[[ $(plutil -extract WKCompanionAppBundleIdentifier raw -o - "$watch/Info.plist") == com.dimasike.currency ]] \
  || { echo 'Wrong Watch companion identifier' >&2; exit 1; }
echo 'Exported iPhone and Watch bundles, versions, profiles, and App Group signatures verified'
