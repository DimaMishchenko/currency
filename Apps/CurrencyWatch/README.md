# Currency Watch

Independent watchOS 26+ converter. Amount, active pair, downloaded rates and history live on Watch. The companion phone sends preferred currencies through the latest WatchConnectivity application context; it never replaces Watch amounts or base currency. No location permission is requested on Watch.

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
