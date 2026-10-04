# Currency Watch

Independent watchOS 26+ converter. Amount, active pair, downloaded rates and history live on Watch. The companion phone sends preferred currencies through the latest WatchConnectivity application context; it never replaces Watch amounts or base currency. No location permission is requested on Watch.

`App` composes the reusable Home and CurrencyDetails models with native Watch presentations, direct rate/history services and App Group persistence shared with CurrencyWatchWidgets. Existing conversion/check-rate Siri actions reuse CurrencyApplication operations. Widgets and controls open validated `currency-watch` routes.

Generate with `tuist generate --no-open --cache-profile none`. Build the `CurrencyWatch` scheme for an explicitly owned watchOS Simulator. Build `CurrencyTests` for regression and sync tests. The iPhone app embeds the Watch app; release signing/export checks require separate profiles for both Watch bundles.

Simulator installs must retain ad-hoc signing so App Group access works:

```sh
set -o pipefail
xcodebuild -workspace Currency.xcworkspace -scheme CurrencyWatch \
  -destination "id=$WATCH_SIMULATOR_UDID" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build | xcbeautify
```
