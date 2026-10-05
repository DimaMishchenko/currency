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

From `Apps/Currency/Tests/E2E`:

```sh
npm ci
npx e2e login openai
npm run typecheck
npm run test:e2e -- tests/converter.e2e.ts
```

Before running, check the configured app exists and record its build identity:

```sh
test -d ../../../../.validation/e2e/DerivedData/Build/Products/Debug-iphonesimulator/Currency.app
shasum -a 256 ../../../../.validation/e2e/DerivedData/Build/Products/Debug-iphonesimulator/Currency.app/Currency.debug.dylib
```

Login is needed only when credentials are unavailable. Authentication stays outside the repository. Run one suite at a time against the explicit owned UDID; keep the simulator/helper warm during iteration. The latest report is `.e2e/report.json`; screenshots are under `.e2e/artifacts/`. Preserve reports before the next run overwrites them.

Choose targets from the changed behavior: use one owned iPhone by default, add iPad for layout, sizing or tablet-specific changes, and run widget journeys for widget or shared-data changes. Additional profiles run when relevant or explicitly requested. Keep journeys shared unless the user flow differs. iPad remains experimental with the driver limitations below; Duo verification is deferred.

For device checks, set `CURRENCY_E2E_TARGET` to `ipad`, `duo-open` or `duo-closed` and use a matching owned simulator UUID. The default remains `iphone`. iPad runs in portrait; Duo uses genuine folding, with landscape for the open panel and portrait for the closed panel. The converter journey switches to the opposite Duo pose and back without resetting, checking EUR 42 / USD 84 in each pose. Duo requires the iOS 27.1 runtime.

Run profiles sequentially on this host. Give each profile its own helper state and report directory:

```sh
export CURRENCY_E2E_TARGET=ipad
export CURRENCY_E2E_UDID=<your-owned-ipad-simulator-uuid>
AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device-$CURRENCY_E2E_TARGET npx e2e run tests/converter.e2e.ts --output .e2e/$CURRENCY_E2E_TARGET
```

Target names keep action recordings separate by profile. Stop the matching helper and simulator after the batch using the shutdown commands below with that profile's state directory.

## Coverage and maintenance

The app-wide [feature map](../../../../Documentation/FeatureMap.md) owns capabilities and expected outcomes, including features without E2E coverage. This table maps representative journeys to its stable IDs; it does not establish coverage of every path within an ID.

| Feature IDs | Journey / initial state | Current coverage |
| --- | --- | --- |
| ONB-01, ONB-02 | [onboarding.e2e.ts](tests/onboarding.e2e.ts), `fresh-onboarding` | CHF/EUR/USD selection, Back, completion and restart (core); interrupted-draft resume is not covered |
| CONV-01, CONV-05 | [converter.e2e.ts](tests/converter.e2e.ts), `ready-converter` | Source amount EUR 42 → USD 84 and restart (core); Duo also changes pose and back, preserving both values. Unfinished editing and secondary editing are not covered |
| CONV-02, CONV-03, CONV-05 | [currency-selection.e2e.ts](tests/currency-selection.e2e.ts), `ready-converter` | Source EUR → USD, add CHF/CZK, remove EUR and restart; exact USD 1 → CHF 0.25/CZK 12.5 (core). Search aliases, categories and reordering are not covered |
| HIST-01, HIST-02, HIST-03, HIST-04 | [converter-details.e2e.ts](tests/converter-details.e2e.ts), `ready-converter` | Core; exact 1 USD = 0.5 EUR, Three months selection, expanded source explanation and close preserve converter values. Passed on merged main on the owned iPhone simulator; live history data and chart correctness are not asserted |
| PREF-01 | [preferences.e2e.ts](tests/preferences.e2e.ts), `ready-converter` | System → Dark persists after restart, converter unchanged; passed live and cached (core). Light/System-following and accent/location/replay paths are not covered |
| WID-02, WID-10, CONV-05 | [home-screen-widget.e2e.ts](tests/home-screen-widget.e2e.ts), `ready-converter` | Default medium Calculator keypad → EUR 42 / USD 84 on Home Screen → same values after app restart (extended) |
| WID-02, WID-10, CONV-05 | [app-to-widget.e2e.ts](tests/app-to-widget.e2e.ts), `ready-converter` | App amount 42 EUR and CHF addition → installed Calculator shows EUR 42 / USD 84 / CHF 21 (extended) |
| WID-04–08, WID-10 | [widget-display.e2e.ts](tests/widget-display.e2e.ts), `ready-converter` | Programmatic Home Screen installation; Board 1/2 and app edit 42/84, Cash CZK 100 ≈ EUR 4, Pocket EUR 5 ≈ USD 10, Mental Math ×2, History rate 2 / +11.11% and visible graph. Additional Calculator/Board/History sizes use `widget-sizes` |
| WID-04, WID-06–07 | [widget-configuration.e2e.ts](tests/widget-configuration.e2e.ts), `ready-converter` | Private intent setup: Pocket reversed pair and restoration, Mental Math division, Custom Board amount/list independence from app input. `widget-configuration`; gallery mode reports explicit skips |
| WID-09, WID-10 | [widget-lock-screen.e2e.ts](tests/widget-lock-screen.e2e.ts), `ready-converter` | Default Dollar Currency Icon installation/reuse and saved Lock Screen display; custom-symbol editing remains uncovered |

Features absent from this table still belong to the app. Select new tests from the feature map when changing their functionality; choose integrated user outcomes and retain numerical/failure-path combinations in native tests. Core replay reliability remains provisional.

Run extended cases separately with `npm run test:e2e:extended`, optionally followed by a file path. Run representative widget cases with `npm run test:e2e:widgets`. Run the additional Home Screen sizes with `AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device npx e2e run --tag widget-sizes`. Keep widgets outside core: their checks still include real system rendering and some model-backed visual assertions. Run the affected widget when its behavior changes, both Calculator sharing journeys for shared-data changes, and the complete widget matrix only for changes affecting every kind or when explicitly requested. Use native tests for the larger configuration and numerical matrix. To run every journey locally:

```sh
AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device npx e2e run
```

Home Screen journeys use private simulator setup by default. Set `CURRENCY_E2E_WIDGET_SETUP=gallery` to exercise system gallery installation instead. The generic helper is [`widgetctl`](https://github.com/DimaMishchenko/widgetctl), installed as a dev dependency pinned to a GitHub commit. Currency identifiers stay in `simulator-widgets.ts`; the helper uses TypeScript and needs no Python runtime. Private setup prepares its helper before launching the app, keeps only the requested Currency kind/family, creates fresh widget identities, moves the widget to the top of its existing page, and reveals it. Test-module cleanup unloads the owned helper, including after failures. Private setup checks persisted placement; the journeys still check rendered data and actual interactions.

The gallery path adds the requested kind and size through the system gallery, including when the Currency app icon is absent. It removes only the previous Currency widget on the owned Home Screen; other apps/widgets remain in place. Keep one Currency widget visible at a time on that simulator. Calculator journeys reuse an existing medium Calculator when its bounds and native currency-button structure match, otherwise install it through the same gallery path. Home Screen cases reset the app’s real shared stores and request a timeline reload. Fixed current rates seed EUR 1 / USD 2; History also gets a fresh one-month EUR/USD series from 1.8 to 2, ending yesterday. App launch arguments do not configure widget extension providers. Display journeys check default configurations. Separate private-configuration journeys cover a reversed EUR/USD pair for Pocket and Mental Math, plus a Custom Board currency list and amount independent of app input. Native Edit Widget picker/save behavior, other pairs, Local currency states, independent calculator instances and custom Lock Screen symbols still need coverage. The Lock Screen case opens Notification Center, long-presses the clock and uses Customise; the owned simulator has no Wallpaper entry in Settings. It requires a fresh visual absence check before adding the default Dollar icon, then checks exactly one icon on the saved screen.

The pinned driver exposes widget descendants with local frames interpreted as screen coordinates, hiding some controls and misdirecting taps. `widget-fixtures.ts` temporarily taps four controls relative to the installed widget’s bounding box using the public Locator API. This is limited to the verified medium, two-currency, English/default-text-size layout on the base iPhone. The aspect-ratio check rejects other families but does not establish support for arbitrary layouts. Native USD 0 → 8 → 84 checks prove each keypad step; the app then must retain EUR 42 / USD 84. Revisit this fallback when widget frame handling is corrected upstream. Three-currency output uses native CHF 21 readiness and a visual assertion for all three amounts because the driver omits the USD node in that layout.

For App Intents changes, also run the existing `NativeIntentTests` Xcode scheme. It uses AppIntentsTesting against the installed Currency app to check resolution, structured results, background execution, routing and view annotations. Keep these contracts there. Agent E2E should add actual system UI journeys: discover/configure/run a Currency action in Shortcuts, or tap the installed widget keypad and verify the app sees the shared change. The widget journey targets the latter; the Shortcuts UI journey is still missing. The converter case does not establish App Intents correctness. `WidgetIntegrationTests` checks the adapter with injected capabilities, not execution through the Home Screen widget.

Use `start('fresh-onboarding')` or `start('ready-converter')` once at the beginning of a case. `fixtures.ts` passes reset arguments only on that first launch. Config retains `-CurrencyE2E` on restart to keep fixed providers without resetting state. Do not put `-CurrencyE2EState` into default launch arguments. A new journey should run independently and prove a user-visible outcome.

Maintain native assertions for exact values and persistence; use agent goals for navigation and vision when accessibility cannot establish an outcome. Diagnose a failed outcome before accepting changed navigation recordings. Preserve normal cache behavior. A new goal records naturally; `--no-cache` is a diagnostic that neither reads nor writes recordings.

Current reliability limitation: the original onboarding/converter pilot has passed individually and together, but repeated replay also exposed neighboring-keypad taps and unstable screen-title cache identities in mobile 0.9.1 / agent-device 0.21.20. The driver derives cache locations from navigation-bar accessibility labels, which can vary on the same screen. Experimental dependency patches were removed because they did not reliably fix the problem. Native outcome assertions remain strict; do not treat this suite as a reliable release gate yet. Cold model-backed onboarding can exceed three minutes, so the test budget is five minutes.

Replay recordings in `.e2e/cache` stay local and are ignored by Git. Fresh checkouts record their own cache; existing local recordings remain reusable. Keep goal wording and test/target identity stable when behavior is unchanged. Bump `app.identity` when fixture semantics change. Use `npx e2e cache ls` or `stats` to inspect recordings and `npx e2e cache clear` to reset them when needed; unused entries are not automatically pruned. Reports, helper state and dependencies are also ignored. Do not share a mutable cache directory across worktrees.

For functional changes, select only affected journeys from the feature map and coverage table, including dependent shared-data flows. Run that selection during iteration and before handoff. Do not run the full core or widget suite by default; expand coverage when the change affects it or the user explicitly requests it. Use manual simulator exploration for missing coverage or diagnosis, then capture the regression in a maintained case. Report the binary used, test selection, failures/skips, warm duration and cache handoffs separately from build/cold preparation. Keep detailed calculations/provider edge cases in Swift tests.

## Latest verification

The expanded coverage uses the owned iPhone 18 Pro / iOS 27.0 simulator. The expanded widget runs used Debug app SHA-256 `89677df62786ea2f359734af83fda0bca1ffd7742eee4cda17641fe9d6571705` (`Currency.debug.dylib`). The Debug build, TypeScript checks, scoped Swift formatting, all 35 native application integration test declarations (49 parameterized executions) and independent review passed. The prior Release build passed before the additive DEBUG-only history fixture.

All 17 journeys have passing evidence across separate batches and focused rechecks; this is not a single green full-suite invocation. The five representative Home Screen display cases initially took **11m 47s**: Board, Cash, Pocket and Mental Math passed, while History failed because the simulator displayed a decimal comma. The corrected exact percentage check accepts either separator; its focused recheck passed in **95s**, plus **15s** driver preparation. The default Lock Screen icon installation passed in **128s**. Its final reuse check, with fresh visual presence/absence guards before adding, passed in **187s**, plus **7s** preparation; exactly one dollar icon remained. An attempted native guard failed because the driver omitted the editor controls despite their presence in the screenshot.

The regression batch passed all 11 selected cases (five core, two Calculator sharing cases and four additional sizes) in **15m 30s**: **15m 9s** tests and runner overhead, plus **21s** engine preparation on an already booted device. No selected case failed or retried. Default cache remained enabled: **12 goals replayed, 1 handed off and 6 missed**, with **35 model calls**. Vision checks require the model; this is not a deterministic or zero-model run.

| Selection | Test duration |
| --- | ---: |
| Five core app journeys | 5m 54s |
| Two Calculator sharing journeys, including gallery fallback | 3m 41s |
| Four additional Home Screen sizes | 5m 54s |

Gallery installation/removal dominates the display journeys. Missing-widget setup passed without relying on a Currency app icon. The current driver still exposes some widget descendants with incorrect local frames; visual checks require exact expected currencies, numbers and readable layout where native accessibility cannot establish the outcome.

Reports and screenshots are preserved under `.validation/e2e/widget-display-native-gallery`, `widget-history`, `widget-expansion-regression`, `widget-lock-screen-passed` and `widget-lock-screen-final`; build and native test logs are alongside them. Default data is checked for all seven kinds and all ten Home Screen kind/family combinations. Other configuration combinations, custom symbols, Local currency, independent instances and every preset interaction remain uncovered. Cache and system-widget automation reliability remain provisional.

After integrating main's physical project reorganization (`b20674d`), E2E moved to `Apps/Currency/Tests/E2E`. The rebuilt Debug app SHA-256 is `660c91e37dfa5121335cca478490b2933b2985a4e1de0d17230f4a5303f19b28`. Generation, navigator coverage, localization checks, TypeScript, scoped formatting and the focused startup integration tests passed. The affected converter/restart journey passed in **45s** with one replayed goal and zero model calls, plus **124s** driver preparation. The widget matrix was not repeated for this folder-only integration. Evidence is under `.validation/e2e/main-integration-*`.

### Programmatic Home Screen setup

On the owned arm64 iPhone with iOS 27.0 and the rebuilt app above, the 11 affected Home Screen journeys took **8m 25s**, plus **15s** engine preparation: ten passed and the medium Board visual check incorrectly rejected its expected empty space. After making that check describe visible entries rather than infer hidden loading state, all three Board cases passed in **2m 48s**. Together these runs verify every affected journey; they are not one green full-matrix invocation. Calculator keypad and both app/widget sharing checks retained their native numerical assertions.

Warm widget placement takes roughly **1–2s**, with **23–34s** warm display journeys and **60–75s** sharing journeys. Cold helper preparation typically took **12–20s**, reaching **47s** under contention during configuration experiments, and is separate from engine preparation. The older gallery matrix took about **15m 30s** with a different test selection and build; it is a historical reference, not a controlled comparison. Reports are under `.e2e/private-widget-matrix`, `.e2e/private-board-visible`, and `.validation/e2e/widget-private-*.log`. Programmatic setup does not prove gallery interaction or Edit Widget picker/save behavior. Configuration journeys use full intent export/apply rather than a fabricated archive; the utility verifies exact target identities and canonical readback. A standalone Pocket probe also checked archive persistence after removing the helper and restarting SpringBoard. iPad, Duo and Lock Screen placement are not validated by this utility.

The three private-configuration journeys passed together in **3m 1s**, plus **19s** engine preparation: Pocket reversal/restoration **50s**, Mental Math division **31s**, and Custom Board **94s**. The strengthened Board recheck passed in **2m 2s**, plus **14s** engine preparation, including **13s** cold helper preparation. Its new 8/16 outcome after app input 42/84 proves a fresh custom calculation, rather than relying only on unchanged 7/14 content. Warm export/apply commands plus persisted verification took roughly **0.6–1s**; the complete journeys still include app preparation, native actions and model-backed rendering checks. Reports: `.e2e/private-widget-configuration` and `.e2e/private-widget-custom-board`.

The extracted `widgetctl` integration passed nine selected iPhone journeys in **9m29s**, plus **37s** engine preparation: all three configuration cases, both Calculator sharing directions, Cash, medium History, large Calculator and small Board. Helper cold preparation was **16–25s** per test module; warm configuration apply plus persisted verification was approximately **0.6–0.8s**. This selection uses normal caching; the report is `.e2e/widgetctl-integration/report.json`. Package host tests and static native compilation run in the [widgetctl repository](https://github.com/DimaMishchenko/widgetctl/actions); Currency CI checks the integration types.

### iPad and Duo trial

All seven cases were selected and executed on each profile with the same Debug app. These were new cache identities, so the runs primarily used the model. Durations below are the runner's reported durations, excluding simulator boot and engine preparation. Focused rechecks followed the full runs; the combined results do not represent a green full-suite invocation.

| Profile | First full run | Duration | Verified across full run and rechecks |
| --- | --- | ---: | --- |
| iPad Pro 11-inch M5, iOS 27.0, portrait | 2 passed / 5 failed | 8m 44s | 5/7 with the local driver fix below: all core cases |
| Duo, iOS 27.1, closed portrait | 3 passed / 4 failed | 10m 48s | 6/7: all five core cases and app-to-widget sharing |
| Duo, iOS 27.1, open landscape | 0 passed / 7 failed | 3m 37s | 0/7; interaction and snapshot failures block the journeys |

The iPad picker failure was traced to regular snapshot projection discarding the toolbar's equal-frame sibling and parent. A small upstream driver patch preserves that geometry in TypeScript and Swift without changing occlusion rules. With that patch, all five core journeys passed together in **5m 50s**, plus **1.4s** preparation. The two destination-addition goals now explicitly preserve the source currency on every device. No app code or iPad-specific journey was added. Patch and evidence: `.validation/e2e/ipad-picker-fix`.

The published `agent-device` 0.21.20 does not include this projection fix. The local dependency swap was removed after validation; adopt the upstream release when available. Both iPad widget cases still fail at initial USD-value readiness because widget descendants are missing from the snapshot. Their recheck took **1m 27s**, with no model calls. No numerical assertion was bypassed.

The clarified currency-management journey also passed on iPhone with the published driver in **2m 28s**, plus **50s** cold preparation. Five obsolete recordings for the old destination-addition goals were removed after both devices passed; all 52 retained entries pass the runner's trace schema validation.

The closed-Duo converter recheck genuinely opened and closed the device without resetting the app, retaining EUR 42 / USD 84 in both screenshots and native assertions. This proves committed-value preservation, not unfinished editing or exhaustive pose coverage. Further Duo work is deferred.

Remaining automation failures are explicit: iPad widget descendants omit the initial USD value. Closed Duo can update the widget from the app, but its keypad test rejects clipped widget bounds; the snapshot viewport was 223×317 while the screenshot was 466×678. Open Duo rejects ordinary controls as covered/off-screen and fails widget snapshots with `regular iOS snapshot node escaped its cumulative clip`. Rebinding the app after folding did not resolve that failure and was removed. These results do not establish an app regression or complete iPad/Duo functionality.

First-boot contention also caused Duo display-query and installation timeouts. Sequential warm-device rechecks passed the affected core journeys. Use the device driver fixes as the next step before accepting these profiles as a gate; do not bypass occlusion or numerical checks to make the suite green. Reports, screenshots and the raw widget geometry are preserved under `.validation/e2e` and the profile output directories.

After the shared fixture/goal corrections, all three affected iPhone cases (converter and both widget directions) passed in **3m 35s**, plus **55s** of engine preparation. One goal replayed and two missed, with 12 model calls. TypeScript checks and independent review passed. Five obsolete goal recordings were removed after these checks; default caching remains enabled.

## Cache limits

Real simulator journeys are local-only. Widgetctl’s host-only tests run in its own CI, without device access or model calls. Cached navigation can replay without a model call, but cache misses, screen-identity mismatches and widget vision assertions still require your ChatGPT login. Keep the default cache enabled; it does not make the entire suite deterministic. Historical replay experiments and reports remain under `.validation/e2e`.

## Shutdown

The helper uses isolated state under `.local/agent-device`. After the development batch, stop only this helper and your simulator:

```sh
AGENT_DEVICE_STATE_DIR="$PWD/.local/agent-device" npx agent-device daemon stop
xcrun simctl shutdown "$CURRENCY_E2E_UDID"
```

`@e2e-dev/mobile` 0.9.2 ships `agent-device` 0.21.20 with the [iOS toolbar occlusion fix](https://github.com/callstack/agent-device/pull/3097), following [upstream E2E PR](https://github.com/tester-army/e2e/pull/791). No dependency override is needed. The state directory keeps this suite’s helper separate from other tasks. Unauthenticated replay is not a supported suite configuration; cache context rejection remains a known limitation.
