# Currency E2E

Local real-app tests using Luna 6 low through your ChatGPT subscription. Debug simulator fixtures supply fixed rates and initial state; native assertions verify exact values and persistence. Release builds do not include the fixture adapter.

## Setup

Requires Node 22.12+, Tuist, xcbeautify, Xcode 27.1 beta and iOS 27.0. From the repository root:

```sh
export DEVELOPER_DIR=/Applications/Xcode27.1Beta.app/Contents/Developer
tuist install
tuist generate --no-open --cache-profile none

set -o pipefail
xcodebuild build -workspace Currency.xcworkspace -scheme Currency -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .validation/e2e/DerivedData CODE_SIGN_IDENTITY=- 2>&1 | xcbeautify

xcrun simctl create 'Currency E2E' com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0
export CURRENCY_E2E_UDID=<your-owned-simulator-uuid>

cd Apps/Currency/Tests/E2E
npm ci
npx e2e login openai
npm run typecheck
npm run test:e2e -- tests/converter.e2e.ts
```

Create the simulator once; log in only when credentials are unavailable. Rebuild when app code, resources or build configuration changes. TypeScript-only edits can reuse the build. Use one runner per owned UDID and keep it warm during iteration.

## Run affected tests

Select journeys using the [feature map](../../../../Documentation/FeatureMap.md) and coverage table below. Include dependent shared-data flows; do not run the full suite by default.

```sh
npm run test:e2e -- tests/currency-selection.e2e.ts
npm run test:e2e:extended -- tests/home-screen-widget.e2e.ts
npm run test:e2e:widgets -- tests/widget-display.e2e.ts

# Additional sizes or private widget configurations:
AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device npx e2e run --tag widget-sizes
AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device npx e2e run tests/widget-configuration.e2e.ts
```

Use iPhone by default. Add iPad for layout or tablet-specific changes with `CURRENCY_E2E_TARGET=ipad` and a matching owned UDID. Keep journeys shared unless the flow differs. Run profiles sequentially, with separate helper state and reports:

```sh
CURRENCY_E2E_TARGET=ipad CURRENCY_E2E_UDID=<owned-ipad-uuid> AGENT_DEVICE_STATE_DIR=$PWD/.local/agent-device-ipad npx e2e run tests/converter.e2e.ts --output .e2e/ipad
```

Results are written to `.e2e/report.json` and screenshots to `.e2e/artifacts/`. Use `--output <directory>` to keep separate runs.

## Coverage

These are representative outcomes, not exhaustive coverage of each feature ID.

| Feature IDs | Test | Outcome |
| --- | --- | --- |
| ONB-01–02 | [onboarding](tests/onboarding.e2e.ts) | Currency selection, Back, completion and restart |
| CONV-01, CONV-05 | [converter](tests/converter.e2e.ts) | EUR 42 → USD 84 persists after restart |
| CONV-02–03, CONV-05 | [currency-selection](tests/currency-selection.e2e.ts) | Change source, add/remove currencies, exact amounts and restart |
| HIST-01–04 | [converter-details](tests/converter-details.e2e.ts) | Rate, period selection, source explanation and return |
| PREF-05, ONB-01–02 | [metal-widget-preview](tests/metal-widget-preview.e2e.ts) | Replayed Calculator and Board showcase previews retain the saved grams preference and converted Gold amount |
| PREF-05, WID-04–08 | [metal-widget-display](tests/metal-widget-display.e2e.ts) | Board, Cash, Pocket, Mental Math and History show Gold amounts and visible measurement units |
| PREF-05, WID-02, WID-10 | [metal-widget](tests/metal-widget.e2e.ts) | Saved grams preference reaches Calculator; keypad edits return to app with matching metal conversion |
| PREF-05, CONV-01, CONV-05 | [metal-measurement](tests/metal-measurement.e2e.ts) | Seeded metal destination units and exact displayed conversions change; grams and seeded metal source weight survive restart |
| PREF-04 | [settings-information](tests/settings-information.e2e.ts) | Rates disclaimer, sources, credits and About legal controls are accessible; returning preserves Settings |
| PREF-01, PREF-04, PREF-06–08 | [preferences](tests/preferences.e2e.ts) | Help feedback and About legal/creator controls are visible; creator contact pills align with native legal rows; light/dark appearance, theme persistence, converter values and readable version are preserved |
| PREF-06, PREF-08 | [creator-contact](tests/creator-contact.e2e.ts) | Website opens dimasike.com in Safari; returning preserves the Settings screen and theme; Feedback in Help opens an Email/X alert, cancellation preserves Settings, selected Email offers a copyable address on simulators without Mail, and selected X opens its website |
| WID-02, WID-10, CONV-05 | [home-screen-widget](tests/home-screen-widget.e2e.ts), [app-to-widget](tests/app-to-widget.e2e.ts) | Calculator keypad → app and app edits → widget |
| WID-04–08, WID-10 | [widget-display](tests/widget-display.e2e.ts) | Board, Cash, Pocket, Mental Math and History data; additional sizes |
| WID-04, WID-06–07 | [widget-configuration](tests/widget-configuration.e2e.ts) | Reversed pairs and Custom Board amount/list independent of app input |
| WID-09–10 | [widget-lock-screen](tests/widget-lock-screen.e2e.ts) | Default Dollar icon installation/reuse and saved display |

For widget/shared-data changes, run the affected widget and both Calculator sharing directions when relevant. Keep numerical/configuration combinations in native tests. App Intents contracts belong in `NativeIntentTests`; a Shortcuts system-UI journey is still missing. Update this table when coverage changes and preserve IDs in the feature map.

## Fixtures, widgets and cache

Start each case once with a matching fixture. `fresh-onboarding` and `ready-converter` cover general flows; `ready-metals` adds Gold as a destination and `ready-metal-source` starts with one troy ounce of Gold for measurement checks. The first launch resets real stores; restart keeps edits. Fixed rates are EUR 1 / USD 2 / CHF 0.5 / CZK 25 / XAU 0.01 troy oz, with seeded EUR/USD history and EUR/Gold history for metal fixtures. Keep `-CurrencyE2EState` out of default launch arguments.

Home Screen setup uses [widgetctl](https://github.com/DimaMishchenko/widgetctl), pinned as a GitHub dev dependency. It installs/configures the requested kind and size, preserves other apps’ widgets and unloads its helper after the module. Tests still validate rendered data and interactions. Set `CURRENCY_E2E_WIDGET_SETUP=gallery` to exercise system installation; private-configuration cases then skip. Lock Screen installation uses system UI.

Cache remains enabled and local, ignored by Git. Fresh checkouts record their own. Inspect it with `npx e2e cache ls` or `stats`; `clear` removes all recordings. Unused entries are not automatically pruned. Keep goal/test identities stable and bump `app.identity` when fixture semantics change. Diagnose failed outcomes before accepting replacement recordings. `--no-cache` neither reads nor writes cache. Visual assertions and cache misses still require model access; these simulator tests run locally, not in CI.

## Limitations

- Menu pickers can ignore whole-row driver taps. Target the visible selected-value text (as in the measurement journey), then select the option by its identifier.
- Replay reliability is provisional: mobile screen identities and keypad targeting have caused misses or failures. Keep native outcome assertions strict.
- The driver misprojects some widget descendants. Calculator tests use a bounded tap workaround for the verified medium, two-currency and three-currency, English iPhone layouts; three-currency output also needs vision.
- iPad picker automation requires a snapshot-projection fix not included in the pinned driver; widget checks are blocked by missing descendants. Duo verification is deferred; widgetctl device placement is verified only on arm64 iPhone/iOS 27.
- The Feedback journey checks the email fallback address and Copy email dismissal. Simulator clipboard contents were verified with device-targeted `simctl pbpaste`; the pinned driver clipboard read can return an empty string for this flow.
- Coin motion is checked visually rather than through a dedicated E2E animation assertion.
- Creator contact controls are covered for visibility and Website navigation; Feedback X navigation and the no-Mail copy-address path are covered. Native email composition/delivery requires a device with a configured Mail account.
- Native Edit Widget picker/save, Local currency states, independent instances and custom Lock Screen symbols remain uncovered. History navigation does not prove live chart data.

## Shutdown

Stop only your helper and simulator; use the matching state directory for alternate profiles:

```sh
AGENT_DEVICE_STATE_DIR="$PWD/.local/agent-device" npx agent-device daemon stop
xcrun simctl shutdown "$CURRENCY_E2E_UDID"
```

Watch metal measurement (WATCH-14) uses the [maintained native Watch journey](../../../CurrencyWatch/README.md#metal-measurement-acceptance). The iPhone E2E driver does not cover Watch. Numerical, stale-draft and preference-sync regressions remain in the native unit test targets.
