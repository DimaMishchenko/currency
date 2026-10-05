# Currency Watch

Independent watchOS 26+ converter. Amount, active pair, downloaded rates and history live on Watch. The shared `MetalUnit` preference supports troy ounces, grams and kilograms across conversions, details, history, widgets and Siri. The Watch measurement picker appears in My Currencies when metals are selected. Cash retains the shared iPhone gram presets; links carry their captured unit so preference changes preserve physical quantity. The companion phone sends preferred currencies and metal measurement through the latest WatchConnectivity application context; it preserves Watch base currency and physical source-metal quantity. No location permission is requested on Watch.

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

## Metal measurement acceptance

The iPhone E2E driver does not cover Watch surfaces. Keep this native Watch journey for WATCH-14 on an explicitly owned simulator; use the selected CompanionSync, Home editing, Watch route and shared metal/widget tests for numerical and synchronization regressions.

1. Select XAU as source with amount 1 and troy ounces. Capture its destination conversions.
2. In My Currencies, choose grams. Expect exactly 31.1034768 g and unchanged destination values. Choose kilograms; expect 0.0311034768 kg with the same values.
3. Set a one-gram amount, change to troy ounces, then open the amount keypad. Expect the full stored converted amount rather than 1; Done must preserve it. Restart and verify the unit and quantity persist.
4. Open a metal amount draft, then accept a newer phone measurement preference. Done must reject the old draft rather than reinterpret its mass; Cancel and reopen uses current input.
5. Configure metal Pocket/Board/History widgets. Their units follow the saved preference. Cash keeps gram presets. A previously rendered Cash link must open the same physical grams after the app measurement changes to kilograms; links carry their original measurement.

Native simulator URL launching through `simctl openurl` may be unavailable on Watch; verify widget navigation through the installed system surface instead. Physical WatchConnectivity transport and spoken Siri remain separate device acceptance.
