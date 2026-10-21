#!/usr/bin/env bash
set -euo pipefail

phase=${1:?Usage: run_native_checks.sh unit|app|watch|intents|harnesses}
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
plan="$RUNNER_TEMP/CurrencyCIPlan.json"
settings=$(python3 - "$plan" <<'PY'
import json
import shlex
import sys

with open(sys.argv[1]) as source:
    plan = json.load(source)
if not isinstance(plan.get('full'), bool):
    raise SystemExit('CI plan must contain a boolean full field')
targets = plan.get('harness_targets')
if not isinstance(targets, list) or not all(isinstance(target, str) and target and not any(character.isspace() for character in target) for target in targets):
    raise SystemExit('CI plan harness_targets must be an array of target names')
print('export TUIST_CURRENCY_CI_HARNESS_TARGETS=' + shlex.quote(' '.join(targets)))
print('export TUIST_CURRENCY_CI_CACHE=' + str(not plan['full']).lower())
PY
)
eval "$settings"
export TUIST_CURRENCY_CI_CLOUD=false
if [[ "${CURRENCY_TUIST_UPLOAD:-false}" == true ]]; then
  export TUIST_CURRENCY_CI_CLOUD=true
fi

derived_data="$RUNNER_TEMP/CurrencyTestsDerivedData"
started=$SECONDS
label=''
result_bundle=''

record_duration() {
  outcome=$?
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '| %s | %ss | %s |\n' "$label" "$((SECONDS - started))" "$outcome" >> "$GITHUB_STEP_SUMMARY"
    if [[ -n "$result_bundle" && -d "$result_bundle" ]] && xcrun xcresulttool get test-results summary --path "$result_bundle" > "$result_bundle.summary.json" && xcrun xcresulttool get log --type build --path "$result_bundle" > "$result_bundle.build.json"; then
      python3 - "$result_bundle.summary.json" "$result_bundle.build.json" "$GITHUB_STEP_SUMMARY" <<'PYTHON'
import json
import sys

with open(sys.argv[1]) as source:
    result = json.load(source)
with open(sys.argv[2]) as source:
    build = json.load(source)
with open(sys.argv[3], 'a') as summary:
    duration = max(0, result['finishTime'] - build['startTime'] - build['duration'])
    summary.write(f"\nBuild: {build['duration']:.1f}s; post-build test session: {duration:.1f}s; "
                  f"{result['passedTests']} passed, {result['failedTests']} failed, "
                  f"{result['skippedTests']} skipped.\n")
PYTHON
    fi
  fi
  exit "$outcome"
}

case "$phase" in
  unit) label='Unit tests, including generation and build' ;;
  app) label='iOS app generation and build' ;;
  watch) label='watchOS app generation and build' ;;
  intents) label='Native intents generation, build and tests' ;;
  harnesses) label='Harness generation and build' ;;
  *) printf 'Unknown native check phase: %s\n' "$phase" >&2; exit 2 ;;
esac
trap record_duration EXIT
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '\n| Native phase (wall time) | Duration | Exit status |\n| --- | ---: | ---: |\n' >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$phase" == unit || "$phase" == intents ]]; then
  if [[ -z "${CURRENCY_TEST_SIMULATOR:-}" ]]; then
    printf 'An owned CURRENCY_TEST_SIMULATOR is required\n' >&2
    exit 1
  fi
fi

if [[ "$phase" == unit ]]; then
  flags=(--selective-testing --binary-cache)
  if [[ "$TUIST_CURRENCY_CI_CACHE" == false ]]; then
    flags=(--no-selective-testing --no-binary-cache)
  fi
  if [[ "${CURRENCY_TUIST_UPLOAD:-false}" != true ]]; then
    flags+=(--no-upload)
  fi
  result_bundle="$RUNNER_TEMP/CurrencyUnitTests.xcresult"
  tuist test CurrencyTests \
    --configuration Debug \
    --skip-quarantine \
    --result-bundle-path "$RUNNER_TEMP/CurrencyUnitTests.xcresult" \
    "${flags[@]}" \
    -- \
    -destination "platform=iOS Simulator,id=$CURRENCY_TEST_SIMULATOR" \
    -derivedDataPath "$derived_data" \
    -collect-test-diagnostics never \
    CODE_SIGN_IDENTITY=- \
    2>&1 | tee "$RUNNER_TEMP/CurrencyUnitTests.log" | xcbeautify
  exit 0
fi

cache_profile=all-possible
if [[ "$TUIST_CURRENCY_CI_CACHE" == false ]]; then
  cache_profile=none
fi
tuist generate --no-open --cache-profile "$cache_profile" 2>&1 | tee "$RUNNER_TEMP/CurrencyNativeGenerate-$phase.log" | xcbeautify

arguments=(-workspace Currency.xcworkspace -configuration Debug -derivedDataPath "$derived_data" CODE_SIGN_IDENTITY=-)
case "$phase" in
  app)
    xcodebuild build "${arguments[@]}" -scheme Currency -destination 'generic/platform=iOS Simulator' 2>&1 | tee "$RUNNER_TEMP/CurrencyNativeBuild-app.log" | xcbeautify
    ;;
  watch)
    xcodebuild build "${arguments[@]}" -scheme CurrencyWatch -destination 'generic/platform=watchOS Simulator' 2>&1 | tee "$RUNNER_TEMP/CurrencyNativeBuild-watch.log" | xcbeautify
    ;;
  harnesses)
    xcodebuild build "${arguments[@]}" -scheme CurrencyHarnesses -destination 'generic/platform=iOS Simulator' 2>&1 | tee "$RUNNER_TEMP/CurrencyNativeBuild-harnesses.log" | xcbeautify
    ;;
  intents)
    result_bundle="$RUNNER_TEMP/CurrencyNativeIntents.xcresult"
    xcodebuild test "${arguments[@]}" \
      -scheme NativeIntentTests \
      -destination "platform=iOS Simulator,id=$CURRENCY_TEST_SIMULATOR" \
      -resultBundlePath "$RUNNER_TEMP/CurrencyNativeIntents.xcresult" \
      -collect-test-diagnostics never \
      -parallel-testing-enabled NO \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 120 \
      -maximum-test-execution-time-allowance 120 \
      2>&1 | tee "$RUNNER_TEMP/CurrencyNativeIntents.log" | xcbeautify
    ;;
esac
