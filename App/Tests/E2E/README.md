# Local agent E2E

The core suite exercises real app journeys for onboarding, converter input, currency management, details/history navigation and appearance persistence. iPhone is the default; iPad and Duo profiles are experimental. Exact fixed-rate outcomes and restart checks verify the result of agent navigation. It uses Luna 6 low through your ChatGPT subscription and the default action cache.

A DEBUG simulator startup adapter supplies fixed rates and named initial states through the real stores. Installation happens once per runner invocation; each case resets independently. Ordinary restart keeps edits. The app’s native UI, rate service, persistence and App Group remain in use. Release builds do not include the adapter.

## Setup

Requires Node 22.12+, Tuist, xcbeautify, Xcode 27.1 beta and iOS 27.0. From the repository root, install/generate when dependencies or the project graph change, including adding files to globbed test targets:

```sh
export DEVELOPER_DIR=/Applications/Xcode27.1Beta.app/Contents/Developer
tuist install
tuist generate --no-open --cache-profile none
```

Build the current worktree whenever app code, resources or build configuration changes. Test-only TypeScript edits can reuse that build:

```sh
set -o pipefail
xcodebuild build -workspace Currency.xcworkspace -scheme Currency -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .validation/e2e/DerivedData CODE_SIGN_IDENTITY=- 2>&1 | xcbeautify
```

Create an owned simulator once and save its UUID:

```sh
xcrun simctl create 'Currency E2E' com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0
export CURRENCY_E2E_UDID=<your-simulator-uuid>
```

From `App/Tests/E2E`:

```sh
npm ci
npx e2e login openai
npm run typecheck
npm run test:e2e
npm run test:e2e -- tests/converter.e2e.ts
```

Before running, check the configured app exists and record its build identity:

```sh
test -d ../../../.validation/e2e/DerivedData/Build/Products/Debug-iphonesimulator/Currency.app
shasum -a 256 ../../../.validation/e2e/DerivedData/Build/Products/Debug-iphonesimulator/Currency.app/Currency.debug.dylib
```

Login is needed only when credentials are unavailable. Authentication stays outside the repository. Run one suite at a time against the explicit owned UDID; keep the simulator/helper warm during iteration. The latest report is `.e2e/report.json`; screenshots are under `.e2e/artifacts/`. Preserve reports before the next run overwrites them.

Choose targets from the changed behavior: use one owned iPhone by default, add iPad for layout, sizing or tablet-specific changes, and run widget journeys for widget or shared-data changes. Additional profiles run when relevant or explicitly requested. Keep journeys shared unless the user flow differs. iPad remains experimental with the driver limitations below; Duo verification is deferred.

For device checks, set `CURRENCY_E2E_TARGET` to `ipad`, `duo-open` or `duo-closed` and use a matching owned simulator UUID. The default remains `iphone`. iPad runs in portrait; Duo uses genuine folding, with landscape for the open panel and portrait for the closed panel. The converter journey switches to the opposite Duo pose and back without resetting, checking EUR 42 / USD 84 in each pose. Duo requires the iOS 27.1 runtime.

Run profiles sequentially on this host. Give each profile its own helper state and report directory:

```sh
export CURRENCY_E2E_TARGET=ipad
export CURRENCY_E2E_UDID=<your-owned-ipad-simulator-uuid>
AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device-$CURRENCY_E2E_TARGET npx e2e run --output .e2e/$CURRENCY_E2E_TARGET
```

Target names keep action recordings separate by profile. Stop the matching helper and simulator after the batch using the shutdown commands below with that profile's state directory.

## Coverage and maintenance

The app-wide [feature map](../../../Documentation/FeatureMap.md) owns capabilities and expected outcomes, including features without E2E coverage. This table maps representative journeys to its stable IDs; it does not establish coverage of every path within an ID.

| Feature IDs | Journey / initial state | Current coverage |
| --- | --- | --- |
| ONB-01, ONB-02 | [onboarding.e2e.ts](tests/onboarding.e2e.ts), `fresh-onboarding` | CHF/EUR/USD selection, Back, completion and restart (core); interrupted-draft resume is not covered |
| CONV-01, CONV-05 | [converter.e2e.ts](tests/converter.e2e.ts), `ready-converter` | Source amount EUR 42 → USD 84 and restart (core); Duo also changes pose and back, preserving both values. Unfinished editing and secondary editing are not covered |
| CONV-02, CONV-03, CONV-05 | [currency-selection.e2e.ts](tests/currency-selection.e2e.ts), `ready-converter` | Source EUR → USD, add CHF/CZK, remove EUR and restart; exact USD 1 → CHF 0.25/CZK 12.5 (core). Search aliases, categories and reordering are not covered |
| HIST-01, HIST-02, HIST-03, HIST-04 | [converter-details.e2e.ts](tests/converter-details.e2e.ts), `ready-converter` | Core; exact 1 USD = 0.5 EUR, Three months selection, expanded source explanation and close preserve converter values. Passed on merged main on the owned iPhone simulator; live history data and chart correctness are not asserted |
| PREF-01 | [preferences.e2e.ts](tests/preferences.e2e.ts), `ready-converter` | System → Dark persists after restart, converter unchanged; passed live and cached (core). Light/System-following and accent/location/replay paths are not covered |
| WID-02, WID-10, CONV-05 | [home-screen-widget.e2e.ts](tests/home-screen-widget.e2e.ts), `ready-converter` | Default medium Calculator keypad → EUR 42 / USD 84 on Home Screen → same values after app restart (extended) |
| WID-02, WID-10, CONV-05 | [app-to-widget.e2e.ts](tests/app-to-widget.e2e.ts), `ready-converter` | App amount 42 EUR and CHF addition → installed Calculator shows EUR 42 / USD 84 / CHF 21 (extended) |

Features absent from this table still belong to the app. Select new tests from the feature map when changing their functionality; choose integrated user outcomes and retain numerical/failure-path combinations in native tests. Core replay reliability remains provisional.

Run extended cases separately with `npm run test:e2e:extended`, optionally followed by a file path. Run both widget cases with `npm run test:e2e:widgets`. Keep them outside core while system-widget automation reliability is provisional. To run all seven locally:

```sh
AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device npx e2e run
```

The widget fixture installs a medium Calculator through the Currency icon’s context menu when absent, then reuses it across cases and runs. The icon is scoped to the Home Screen grid to exclude iPad Dock suggestions; Done is used only when editing controls remain. Use exactly one Default medium Calculator on this owned simulator. Each case resets the app’s real shared stores and requests a widget timeline reload; it verifies app EUR 1 / USD 2, then waits up to 30 seconds for the widget’s initial USD 2 value. App launch arguments do not configure widget extension providers. Full system gallery navigation, Edit Widget, removal, Custom lists and other widget kinds/families remain uncovered. Device-specific gaps are recorded below.

The pinned driver exposes widget descendants with local frames interpreted as screen coordinates, hiding some controls and misdirecting taps. `widget-fixtures.ts` temporarily taps four controls relative to the installed widget’s bounding box using the public Locator API. This is limited to the verified medium, two-currency, English/default-text-size layout on the base iPhone. The aspect-ratio check rejects other families but does not establish support for arbitrary layouts. Native USD 0 → 8 → 84 checks prove each keypad step; the app then must retain EUR 42 / USD 84. Revisit this fallback when widget frame handling is corrected upstream. Three-currency output uses native CHF 21 readiness and a visual assertion for all three amounts because the driver omits the USD node in that layout.

For App Intents changes, also run the existing `NativeIntentTests` Xcode scheme. It uses AppIntentsTesting against the installed Currency app to check resolution, structured results, background execution, routing and view annotations. Keep these contracts there. Agent E2E should add actual system UI journeys: discover/configure/run a Currency action in Shortcuts, or tap the installed widget keypad and verify the app sees the shared change. The widget journey targets the latter; the Shortcuts UI journey is still missing. The converter case does not establish App Intents correctness. `WidgetIntegrationTests` checks the adapter with injected capabilities, not execution through the Home Screen widget.

Use `start('fresh-onboarding')` or `start('ready-converter')` once at the beginning of a case. `fixtures.ts` passes reset arguments only on that first launch. Config retains `-CurrencyE2E` on restart to keep fixed providers without resetting state. Do not put `-CurrencyE2EState` into default launch arguments. A new journey should run independently and prove a user-visible outcome.

Maintain native assertions for exact values and persistence; use agent goals for navigation and vision when accessibility cannot establish an outcome. Diagnose a failed outcome before accepting changed navigation recordings. Preserve normal cache behavior. A new goal records naturally; `--no-cache` is a diagnostic that neither reads nor writes recordings.

Current reliability limitation: the original onboarding/converter pilot has passed individually and together, but repeated replay also exposed neighboring-keypad taps and unstable screen-title cache identities in mobile 0.9.1 / agent-device 0.21.20. The driver derives cache locations from navigation-bar accessibility labels, which can vary on the same screen. Experimental dependency patches were removed because they did not reliably fix the problem. Native outcome assertions remain strict; do not treat this suite as a reliable release gate yet. Cold model-backed onboarding can exceed three minutes, so the test budget is five minutes.

Commit reviewed `.e2e/cache` entries, checking recorded text and actions. Keep goal wording and test/target identity stable when behavior is unchanged. Bump `app.identity` when fixture semantics change. Reports, helper state and dependencies are ignored. Do not share a mutable cache directory across worktrees.

For functional changes, run the affected journey during iteration and the core suite before handoff. Use manual simulator exploration for missing coverage or diagnosis, then capture the regression in a maintained case. Report the binary used, test selection, failures/skips, warm duration and cache handoffs separately from build/cold preparation. Keep detailed calculations/provider edge cases in Swift tests.

## Latest verification

All seven journeys passed together on `main` (`6eb6ca2`) plus these local changes on the owned iPhone 18 Pro / iOS 27.0 simulator. The current Debug app SHA-256 is `9e53bd322c724b45ca8038fcbe6270b6966b3733bcb7c089676c884d3fd2d5e2` (`Currency.debug.dylib`). Debug and Release builds, TypeScript checks, all 33 native application integration tests and independent review passed.

The final polished run took **10m 30s** wall time excluding build: **9m 52s** for tests, **34s** for driver preparation and approximately 4s of runner overhead. All seven passed without retries or skips. Default cache remained enabled: **7 goals replayed, 1 handed off and 11 missed**, with **50 model calls**. The two final widget vision assertions used the model; initial widget readiness uses native assertions. This is not a deterministic or zero-model run.

| Journey | Duration |
| --- | ---: |
| App amount/currency → Home Screen widget | 108s |
| Details/range/source/close | 53s |
| Converter amount/restart | 35s |
| Source/add/remove/restart | 142s |
| Widget keypad → shared app amount | 53s |
| Onboarding/back/restart | 144s |
| Theme/restart | 56s |

Both widget cases took **160s** combined with the medium Calculator already installed. Installation was exercised in an earlier run; these timings cover reuse. Details and converter replayed without model calls. The revised app-to-widget amount goal recorded a new trace, while currency selection, onboarding and Settings needed model recovery. One obsolete amount-entry recording was removed after the replacement passed.

Preserved evidence is `.validation/e2e/final-polish-report.json`, `final-polish-summary.md`, `final-polish-timing.json` and `final-polish-artifacts`. Build and native validation logs are alongside them. Cache reliability remains provisional; this suite is not a release gate. System-gallery/configuration/removal, other widget kinds/families and chart correctness remain uncovered.

### iPad and Duo trial

All seven cases were selected and executed on each profile with the same Debug app. These were new cache identities, so the runs primarily used the model. Durations below are the runner's reported durations, excluding simulator boot and engine preparation. Focused rechecks followed the full runs; the combined results do not represent a green full-suite invocation.

| Profile | First full run | Duration | Verified across full run and rechecks |
| --- | --- | ---: | --- |
| iPad Pro 11-inch M5, iOS 27.0, portrait | 2 passed / 5 failed | 8m 44s | 5/7 with the local driver fix below: all core cases |
| Duo, iOS 27.1, closed portrait | 3 passed / 4 failed | 10m 48s | 6/7: all five core cases and app-to-widget sharing |
| Duo, iOS 27.1, open landscape | 0 passed / 7 failed | 3m 37s | 0/7; interaction and snapshot failures block the journeys |

The iPad picker failure was traced to regular snapshot projection discarding the toolbar's equal-frame sibling and parent. A small upstream driver patch preserves that geometry in TypeScript and Swift without changing occlusion rules. With that patch, all five core journeys passed together in **5m 50s**, plus **1.4s** preparation. The two destination-addition goals now explicitly preserve the source currency on every device. No app code or iPad-specific journey was added. Patch and evidence: `.validation/e2e/ipad-picker-fix`.

The published `agent-device` 0.21.20 override does not include this projection fix. The local dependency swap was removed after validation; adopt the upstream release when available. Both iPad widget cases still fail at initial USD-value readiness because widget descendants are missing from the snapshot. Their recheck took **1m 27s**, with no model calls. No numerical assertion was bypassed.

The clarified currency-management journey also passed on iPhone with the published driver in **2m 28s**, plus **50s** cold preparation. Five obsolete recordings for the old destination-addition goals were removed after both devices passed; all 52 retained entries pass the runner's trace schema validation.

The closed-Duo converter recheck genuinely opened and closed the device without resetting the app, retaining EUR 42 / USD 84 in both screenshots and native assertions. This proves committed-value preservation, not unfinished editing or exhaustive pose coverage. Further Duo work is deferred.

Remaining automation failures are explicit: iPad widget descendants omit the initial USD value. Closed Duo can update the widget from the app, but its keypad test rejects clipped widget bounds; the snapshot viewport was 223×317 while the screenshot was 466×678. Open Duo rejects ordinary controls as covered/off-screen and fails widget snapshots with `regular iOS snapshot node escaped its cumulative clip`. Rebinding the app after folding did not resolve that failure and was removed. These results do not establish an app regression or complete iPad/Duo functionality.

First-boot contention also caused Duo display-query and installation timeouts. Sequential warm-device rechecks passed the affected core journeys. Use the device driver fixes as the next step before accepting these profiles as a gate; do not bypass occlusion or numerical checks to make the suite green. Reports, screenshots and the raw widget geometry are preserved under `.validation/e2e` and the profile output directories.

After the shared fixture/goal corrections, all three affected iPhone cases (converter and both widget directions) passed in **3m 35s**, plus **55s** of engine preparation. One goal replayed and two missed, with 12 model calls. TypeScript checks and independent review passed. Five obsolete goal recordings were removed after these checks; default caching remains enabled.

## Cache limits

This suite is local-only. Cached navigation can replay without a model call, but cache misses, screen-identity mismatches and widget vision assertions still require your ChatGPT login. Keep the default cache enabled; it does not make the entire suite deterministic. Historical replay experiments and reports remain under `.validation/e2e`.

## Shutdown

The helper uses isolated state under `.local/agent-device`. After the development batch, stop only this helper and your simulator:

```sh
AGENT_DEVICE_STATE_DIR="$PWD/.local/agent-device" npx agent-device daemon stop
xcrun simctl shutdown "$CURRENCY_E2E_UDID"
```

The driver override supplies the [iOS toolbar occlusion fix](https://github.com/callstack/agent-device/pull/3097); [upstream E2E PR](https://github.com/tester-army/e2e/pull/791) proposes the dependency update. The state directory keeps this suite’s helper separate from other tasks. Revisit the dependency override after the upstream update is released. Unauthenticated replay is not a supported suite configuration; cache context rejection remains a known limitation.
