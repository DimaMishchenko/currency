# Currency Watch

Independent watchOS 26+ converter. Amount, active pair, downloaded rates and history live on Watch. The shared `MetalUnit` preference supports troy ounces, grams and kilograms across conversions, details, history, widgets and Siri. Watch follows the iPhone app measurement setting through companion preference sync; it has no measurement picker. Cash retains the shared iPhone gram presets; links carry their captured unit so preference changes preserve physical quantity. The companion phone sends preferred currencies and metal measurement through the latest WatchConnectivity application context; it preserves Watch base currency and physical source-metal quantity. No location permission is requested on Watch.

`App` composes the reusable Home and CurrencyDetails models with native Watch presentations, direct rate/history services and App Group persistence shared with CurrencyWatchWidgets. Existing conversion/check-rate Siri actions reuse CurrencyApplication operations. Widgets and controls open validated `currency-watch` routes.

Generate with `tuist generate --no-open --cache-profile none`. Build the `CurrencyWatch` scheme for an explicitly owned watchOS Simulator. Build `CurrencyTests` for regression and sync tests. The iPhone app embeds the Watch app; release signing/export checks require separate profiles for both Watch bundles.

Simulator builds need signing for App Group access. Native App Intent entity configuration also needs a development signature with a team identity: ad-hoc builds may display saved choices in the editor but resolve those choices as empty, causing widgets to follow Watch defaults instead.

Build for an owned simulator, then sign the two executable bundles with a valid installed Apple Development identity before installation. Xcode may still use ad-hoc signing for simulator products even when `CODE_SIGN_IDENTITY` is overridden.

```sh
set -o pipefail
xcodebuild -workspace Currency.xcworkspace -scheme CurrencyWatch \
  -destination "id=$WATCH_SIMULATOR_UDID" \
  -derivedDataPath "$WATCH_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build 2>&1 | xcbeautify

WATCH_APP="$WATCH_DERIVED_DATA/Build/Products/Debug-watchsimulator/CurrencyWatch.app"
codesign --force --sign "$WATCH_DEVELOPMENT_IDENTITY" \
  --preserve-metadata=entitlements --generate-entitlement-der \
  "$WATCH_APP/PlugIns/CurrencyWatchWidgets.appex"
codesign --force --sign "$WATCH_DEVELOPMENT_IDENTITY" \
  --preserve-metadata=entitlements --generate-entitlement-der "$WATCH_APP"
codesign -dv "$WATCH_APP/PlugIns/CurrencyWatchWidgets.appex"
xcrun simctl install "$WATCH_SIMULATOR_UDID" "$WATCH_APP"
```

Confirm `TeamIdentifier` matches the project team. Verify a custom pair such as GBP/CZK through the native widget editor, installed Smart Stack and corner complication, rather than accepting a default EUR/USD rendering as configuration proof. Board/Favorite Pairs must also retain configured amount/targets; Cash must use its configured currencies; History must retain its pair/range. Snapshots use configured cached data, while timeline refreshes fetch live data.

## Amount editing acceptance

For WATCH-01–02, use one explicitly owned Watch simulator, then repeat the assistive-input checks on a physical Watch. The phone E2E driver does not cover Watch. Amount entry appends to the existing draft; there is no replacement mode. The amount uses the primary foreground before and after every key. The editor keeps the keypad in the available height when its scalable rows fit; smaller viewports at larger text sizes allow vertical scrolling rather than shrinking the digits. Long draft values scroll horizontally and retain their full accessibility value.

1. Save an initial amount of 100. Open the amount editor and press 5. Expect 1005; press Delete once and expect 100. The initial amount and both resulting drafts must remain white in the Watch dark interface.
2. Press the locale's decimal separator and 5. Expect 100.5 (100,5 in a comma-decimal locale). Press the separator again; it must not add a second decimal. Delete removes the final digit, then the separator. Deleting down to the last digit yields 0.
3. Change a draft and use the native Cancel/dismiss action. The converter must retain its saved amount. Reopen, make a new edit, and choose Done. Confirm the converter and its destination conversions use the new amount. Terminate and relaunch; the saved amount must persist.
4. With VoiceOver, focus the amount before and after editing. Expect the localized Amount label and the complete current draft value, including its decimal separator. Activate digits, Decimal separator, Delete digit, Done and Cancel; verify their actual outcomes and focus restoration. An accessibility tree alone does not prove spoken feedback or task completion.
5. On the smallest supported Watch viewport, compare default and maximum Watch text size with Bold Text off/on. Repeat the short draft and a 14-digit amount with a decimal. Verify readable digits, all twelve reachable keys, Done/Cancel, horizontal access to the complete long draft and any needed vertical scrolling. Do not count smaller type or VoiceOver as the visual enlargement alternative.
6. Repeat editing with Reduce Motion and Increase Contrast enabled. Confirm amounts do not change color to indicate editing state, numeric transitions settle without spatial animation under Reduce Motion, and value/key contrast remains readable over the actual glass backgrounds.

Record the owned UDID, text-size/settings, expected and observed values, screenshots and any driver limitation in ignored local evidence. Do not mark this journey passed from a build or shared conversion-model tests.

## Enlarged details and complication acceptance

For WATCH-04–05, compare default and maximum Watch text size on a small Watch viewport. Read the full pair, selected range, latest numeric value and both endpoint dates. Header/date content must remain readable as rows grow or stack, and the chart must grow with text size. Scroll to the reference explanation and any cached/unavailable issue. With VoiceOver, explore native chart observations and their dates/values as well as the range control; the pair label alone is insufficient history access.

Installed accessory complications have system-defined layouts. This app supports rectangular, circular and inline families, plus Pocket's corner family; it does not implement an X-Large family. Keep these constrained summaries compact and verify their actual app alternatives instead of assuming an unsupported large complication exists:

- Pocket, Cash, Board and Favorite Pairs link to the converter with a captured pair and amount. Check a nondefault pair and long amount at maximum Watch text size after opening each supported surface. Cash links must preserve their captured metal quantity. Favorite Pairs has separate per-pair links; verify each selected pair. Mental Math opens the captured conversion; the app's full source/result values provide the conversion outcome, while its compact arithmetic rule remains in the complication.
- History opens details for its captured pair. Its route does not carry the selected history range. Select that same range in the app and verify the enlarged values, dates and chart. Do not claim automatic preservation of the complication's period or a complete equivalent summary from the link alone.

Check saved/unavailable states, native return navigation and actual installed-family contrast separately. These are maintained acceptance instructions, not a record that accessibility support labels have passed.

## Rate provider acceptance

Use one explicitly owned Watch simulator and device-targeted controls. Keep the independent Watch networking path active. Coin Metrics is the standard current crypto and intraday source; Fawaz provides the automatic daily-rate fallback.

1. Install CurrencyWatch. Launch from a fresh container, add BTC to My Currencies and open Bitcoin details. The History range picker must offer One day alongside the daily ranges. Select it and verify a rendered BTC/USD chart or an explicit network issue; availability alone does not prove downloaded reference observations.
2. Return, terminate and relaunch the app. Verify the selected pair and available One day range persist. Capture native accessibility state and screenshots with the owned UDID.
3. Verify a failed current Coin Metrics refresh retains a valid cached quote or uses the available Fawaz daily fallback with its original provenance. An incomplete 1D response must remain explicitly cached or unavailable; it must not become a daily fallback chart.
4. If checking deterministic amounts, seed a coherent real `rates.json` with distinct Coin Metrics/Fawaz values and daily fallbacks before launch; record whether direct network refresh replaced it. Seed chart data only in the matching `history-v3-BTC-USD-<range>.json` namespace.

Use `serve-sim` with the Watch UDID for native controls and screenshots; the iPhone E2E runner does not support this surface. If the Watch accessibility tree contains only an application root, stop automated picker navigation and record that gap; `simctl openurl` may also be unsupported. Save local evidence outside tracked documentation. A compiled Watch target, fixture inspection or failed driver connection does not count as a completed native journey. Spoken Siri, physical companion transport and installed complication configuration remain separate acceptance checks.

## History loading acceptance

For WATCH-04–05, use an owned Watch simulator and open a favorite currency's details. Keep the chart row visible while changing ranges. Check the first load, Month → Year → Month, and rapid changes while a request is pending. An uncached/pending request must show the animated history spinner (`watch.details.loading`), then replace it with the selected range's chart or explicit unavailable state. The row must not become blank after its first chart. A completed cache hit may replace the chart immediately without an artificial loading delay. Late responses must not replace the selected range.

The shared `CurrencyDetailsTests` exercise Month → Year → Month with suspended responses, checking that previous chart data/issues disappear during loading and that each requested result replaces the loader. The native journey additionally checks spinner rendering after Watch list-row reuse. If the Watch accessibility tree exposes only the app root, picker automation is blocked; model tests alone do not prove the native spinner. Preserve screenshots of initial and repeated pending requests, and distinguish controlled delayed-response rendering checks from live picker/provider acceptance.

## Metal measurement acceptance

The iPhone E2E driver does not cover Watch surfaces. Keep this native Watch journey for WATCH-14 on an explicitly owned simulator; use the selected CompanionSync, Home editing, Watch route and shared metal/widget tests for numerical and synchronization regressions.

1. Select XAU as source with amount 1 and troy ounces. Capture its destination conversions.
2. Change the iPhone app setting to grams and accept its newer preference context on Watch. Expect exactly 31.1034768 g and unchanged destination values. Repeat with kilograms; expect 0.0311034768 kg with the same values. My Currencies must have no measurement picker.
3. Set a one-gram amount, sync the phone setting back to troy ounces, then open the amount keypad. Expect the full stored converted amount rather than 1; Done must preserve it. Restart and verify the unit and quantity persist.
4. Open a metal amount draft, then accept a newer phone measurement preference. Done must reject the old draft rather than reinterpret its mass; Cancel and reopen uses current input.
5. Configure metal Pocket/Board/History widgets. Their units follow the saved preference. Cash keeps gram presets. A previously rendered Cash link must open the same physical grams after the app measurement changes to kilograms; links carry their original measurement.

Native simulator URL launching through `simctl openurl` may be unavailable on Watch; verify widget navigation through the installed system surface instead. Physical WatchConnectivity transport and spoken Siri remain separate device acceptance.
