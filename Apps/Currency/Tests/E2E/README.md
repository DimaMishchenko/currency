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
npm run test:e2e:widgets -- tests/widget-history-sync.e2e.ts tests/widget-quote-handoff.e2e.ts
npm run test:e2e:widgets -- tests/widget-input-refresh.e2e.ts tests/app-to-widget.e2e.ts tests/home-screen-widget.e2e.ts

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
| CONV-01, HIST-01–04, PREF-04 | [provider-policy](tests/provider-policy.e2e.ts) | Configured Fawaz/Coin Metrics conversion, 24-hour minute-reference provenance, All monthly sources, no spurious USD approximation and retained non-USD daily-FX notices, 1D capability, source credits and saved-cache compatibility after restart |
| HIST-03, HIST-05 | [history-time-zone](tests/history-time-zone.e2e.ts) | Real app 1D/1W chart and expanded history endpoints follow Los Angeles/Tokyo process time zones, saved times stay local, compact sources show provider/observation without sampling-zone copy, redundant Observed/Retrieved rows stay hidden, and monthly reference dates stay on their provider calendar day |
| RATE-01–02 | [rates-time-zone](tests/rates-time-zone.e2e.ts) | Rates retrieval/last-check and BTC observation timestamps follow Los Angeles/Tokyo process time zones with one explicit Times label; quote sources omit bare GMT and daily USD Published dates retain their provider calendar day |
| HIST-02 | [history-archive](tests/history-archive.e2e.ts) | With the seeded All cache removed, the real bundled BTC/USD history starts in 2010 and exposes monthly source/date information |
| HIST-02–04 | [history-cache](tests/history-cache.e2e.ts) | A legacy Fawaz USD/AED month refreshes to the real preferred source; an out-of-range month cache is replaced with recent dated observations; exact repaired history, source and migration marker survive relaunch. Flat rates remain valid; requires network |
| HIST-02, HIST-04, RATE-01 | [fiat-history-live](tests/fiat-history-live.e2e.ts) | Refresh production rates, load complete Frankfurter USD/EUR and AED/EUR years and bundled monthly All archive from 2010, record cold/All/warm times and prove exact yearly cache reuse after relaunch; requires network |
| HIST-02–03, WID-08 | [converted-crypto-history](tests/converted-crypto-history.e2e.ts) | An installed BTC/EUR History widget fetches a complete live day with the app closed and retains its historical USD/EUR rate, provider and publication date; requires network |
| RATE-01–02, HIST-01–04, CONV-05, PREF-04 | [live-app-provider](tests/live-app-provider.e2e.ts) | Disable the fixture network adapter, force-refresh all 22 crypto quotes, inspect the real phone USD and EUR 1D charts and bundled All history from 2010, then relaunch and verify saved input/chart reuse; requires network |
| HIST-02–03 | [weekly-japanese](tests/weekly-japanese.e2e.ts) | Japanese Bitcoin details select 1W through the adaptive period menu and show the natural hourly-reference label from the owning catalog without redundant source sampling time-zone text |
| HIST-01–04, CONV-05 | [live-weekly-history](tests/live-weekly-history.e2e.ts) | Fetch production BTC/USD and BTC/EUR 1W charts, assert at least 160 hourly Coin Metrics observations across nearly seven days, native conversion provenance and same-hour relaunch cache reuse; requires network |
| HIST-02, WID-08 | [widget-live-provider](tests/widget-live-provider.e2e.ts) | With the app terminated and the seeded 1D cache removed, an installed widget fetches and persists a complete live Coin Metrics day; requires network |
| HIST-01–04 | [converter-details](tests/converter-details.e2e.ts) | Rate, period selection, source explanation and return |
| CONV-02–03, CONV-05, HIST-01–04 | [details-reference](tests/details-reference.e2e.ts) | Bitcoin Details retains EUR/USD/CZK/CHF references and non-USD approximation provenance; ETH/BTC and VND/BTC stay nonzero at exact current and 1M/1D values; selected sources and pairs survive restart |
| PREF-05, ONB-01–02 | [metal-widget-preview](tests/metal-widget-preview.e2e.ts) | Replayed Calculator and Board showcase previews retain the saved grams preference and six-significant-digit converted Gold amount |
| PREF-05, WID-04–08 | [metal-widget-display](tests/metal-widget-display.e2e.ts) | Board, Cash, Pocket, Mental Math and History show rounded Gold amounts and visible measurement units |
| PREF-05, WID-02, WID-10 | [metal-widget](tests/metal-widget.e2e.ts) | Saved grams preference reaches Calculator; keypad edits return to app with matching six-significant-digit metal conversion |
| PREF-05, CONV-01, CONV-05 | [metal-measurement](tests/metal-measurement.e2e.ts) | Metal destinations use six significant digits without trailing zeros; tiny kilogram results stay nonzero; the exact 31.1034768 g source weight survives restart |
| PREF-04 | [settings-information](tests/settings-information.e2e.ts) | Rates disclaimer, sources, credits and About legal/source controls are accessible; Open source opens the Currency repository in Safari; returning preserves Settings |
| PREF-01, PREF-04, PREF-06–08 | [preferences](tests/preferences.e2e.ts) | Help feedback and About legal/creator controls are visible; creator contact pills align with native legal rows; light/dark appearance, theme persistence, converter values and readable version are preserved |
| PREF-09, ONB-01, ONB-03–04, WID-01 | [widget-tutorial-icon](tests/widget-tutorial-icon.e2e.ts) | First-launch gallery illustration uses World Yen / Yuan; Grid Bitcoin selection survives restart and appears in replayed tutorial artwork in light and dark appearance; restores World and prior appearance |
| PREF-09 | [app-icon](tests/app-icon.e2e.ts) | World and Grid sections expose six named currency tiles each. World Euro and Grid Bitcoin use the native alternate icon operation, remain selected after restart, and restore the primary World Yen / Yuan icon; dismisses native confirmation when shown |
| PREF-06, PREF-08 | [creator-contact](tests/creator-contact.e2e.ts) | Website opens dimasike.com in Safari; returning preserves the Settings screen and theme; Feedback in Help opens an Email/X alert, cancellation preserves Settings, selected Email offers a copyable address on simulators without Mail, and selected X opens its website |
| WID-02, WID-10 | [widget-context-recovery](tests/widget-context-recovery.e2e.ts) | With a full 128-context legacy cache, installed Calculator loads, accepts USD 42, Pocket Rate loads, and readding Calculator preserves input without rewriting the aggregate |
| WID-02, WID-10 | [widget-input-refresh](tests/widget-input-refresh.e2e.ts) | An entered USD 42 stays fixed after a controlled rate-cache update and app foreground refresh; its EUR result changes from 21 to 14 |
| WID-02, WID-10, CONV-05 | [home-screen-widget](tests/home-screen-widget.e2e.ts), [app-to-widget](tests/app-to-widget.e2e.ts) | Calculator keypad → app and app edits → widget |
| CONV-01, RATE-01–02, HIST-02, WID-08 | [widget-history-sync](tests/widget-history-sync.e2e.ts) | App home and installed BTC/USD small 1D and medium 1W widgets initially share 52,500; advancing shared rates to 55,000 and requesting only the day widget must converge both widgets with +10.00%/+37.50% changes and immutable quote contexts; native cache assertions require a complete hourly week and vision checks weekly detail |
| CONV-01, RATE-01–02, WID-08, WID-10 | [widget-quote-handoff](tests/widget-quote-handoff.e2e.ts) | Actual widget tap retains an immutable 52,500 quote context, then displays a newer shared 55,000 quote without another refresh attempt |
| WID-04–08, WID-10 | [widget-display](tests/widget-display.e2e.ts) | Board, Cash, Pocket, Mental Math and History data; additional sizes |
| WID-04, WID-06–07 | [widget-configuration](tests/widget-configuration.e2e.ts) | Reversed pairs and Custom Board amount/list independent of app input |
| WID-09–10 | [widget-lock-screen](tests/widget-lock-screen.e2e.ts) | Default Dollar icon installation/reuse and saved display |

For widget/shared-data changes, run the affected widget and both Calculator sharing directions when relevant. Keep numerical/configuration combinations in native tests. App Intents contracts belong in `NativeIntentTests`; that suite seeds `ready-converter` once, keeps fixed rates on later launches and verifies saved Settings preferences across app termination. It does not prove live provider coverage; a Shortcuts system-UI journey is still missing. Update this table when coverage changes and preserve IDs in the feature map.

## Fixtures, widgets and cache

Start each case once with a matching fixture. `fresh-onboarding` and `ready-converter` cover general flows; `ready-metals` adds Gold as a destination and `ready-metal-source` starts with one troy ounce of Gold for measurement checks. The first launch resets real stores; restart keeps edits. Fixed rates are EUR 1 / USD 2 / CHF 0.5 / CZK 25 / XAU 0.01 troy oz, with versioned reference-history caches for EUR/USD, EUR/Gold, BTC against USD/EUR/CZK/CHF/VND and ETH/BTC. Ethereum has distinct live/daily fixture quotes; VND exercises tiny crypto reference values. `ready-history-sync` starts BTC 1 → USD 52,500 and seeds the same timestamped current quote plus distinct day/week History values before widget reload. Crypto week fixtures contain 169 hourly Coin Metrics observations across seven days with visible rises and dips; the History sync week starts at 40,000 and ends at the shared 52,500. `ready-crypto` starts USD 1 → Bitcoin: 0.00002 from Coin Metrics, with a distinct 0.00001 Fawaz daily fallback stored alongside it. Restart omits fixture state and preserves the real stores. Keep `-CurrencyE2EState` out of default launch arguments.

The history and Rates time-zone journeys launch only the selected simulator app with `SIMCTL_CHILD_TZ` and retarget the existing driver session without relaunching. They derive expected timestamps from the app’s seeded caches and do not change simulator or host time-zone settings. They require the normal debug simulator build and the configured owned UDID.

Run the provider journey with the normal app build. It verifies the standard Coin Metrics current rate, 1D capability, source credits and restart behavior. The fixture cache identity is `currency-fixtures-v15-source-zone`; daily fiat fixtures include the current history-policy marker and All fixtures use completed months; rebuild after app or fixture changes.

```sh
npm run test:e2e -- tests/provider-policy.e2e.ts
```

The fixtures use the production provider decoders with a fixed HTTP client. Fawaz supplies daily rates; Coin Metrics supplies current crypto reference prices. Fresh chart caches include a full day of five-minute sampled reference observations, full week of hourly reference observations and monthly All provenance; they avoid live network timing. These fixture journeys do not prove live provider coverage or provider-shortfall handling. This journey verifies the standard provider configuration and same-build relaunch with compatible reference caches.

Home Screen setup uses [widgetctl](https://github.com/DimaMishchenko/widgetctl), pinned as a GitHub dev dependency. It installs/configures the requested kind and size, preserves other apps’ widgets and unloads its helper after the module. Tests still validate rendered data and interactions. Set `CURRENCY_E2E_WIDGET_SETUP=gallery` to exercise system installation; private-configuration cases then skip. Lock Screen installation uses system UI.

Private History display fixtures explicitly configure EUR/USD/month because replacement can retain the previous pair. The range-sync journey keeps small 1D and medium 1W installed, first checking the shared 52,500 rate/date and respective +5.00%/+31.25% changes. With the app closed, it atomically advances shared rates to a fresh 55,000 and reconfigures only the small day widget. Both installed widgets must then show 55,000 with +10.00%/+37.50%; persisted quote contexts must include 55,000 while the original 52,500 record remains immutable. Contexts deduplicate by pair and snapshot, so the range-specific outcomes are checked on each widget. Device-targeted reveal handles pages during initial setup only; after the rate change, observation uses native locators and horizontal Home Screen swipes without revealing through widgetctl, reconfiguring the sibling or reopening the app. Fresh `checkedAt` prevents provider refresh during the normal rate gate; a changed persisted timestamp fails the journey. WidgetKit may defer sibling delivery, so a timeout remains a failure to prove convergence and must not be repaired by reloading the sibling. Percentages and dates use native assertions; rates and graphs use vision because the driver can duplicate currency-row labels. The journey retries once across a UTC-hour boundary. The handoff journey advances only the authoritative cache to 55,000, verifies the captured widget context remains 52,500, then taps the installed widget and verifies eventual app 55,000 without a new refresh attempt. Native scene tests verify the initial captured snapshot because the driver may observe the app after its 1.5-second handoff window. After the actual widget tap, vision verifies the app is foreground before a non-relaunching open retargets the driver from SpringBoard for native assertions. Board checks reveal the widget after returning from the app.

Cache remains enabled and local, ignored by Git. Fresh checkouts record their own. Inspect it with `npx e2e cache ls` or `stats`; `clear` removes all recordings. Unused entries are not automatically pruned. Keep goal/test identities stable and bump `app.identity` when fixture semantics change. Diagnose failed outcomes before accepting replacement recordings. `--no-cache` neither reads nor writes cache. Visual assertions and cache misses still require model access; these simulator tests run locally, not in CI.

The app-icon file separates layout from native icon changes. Run both core tests on iPhone. For iPad layout and all twelve accessible names without invoking the native confirmation, select the layout title:

```sh
CURRENCY_E2E_TARGET=ipad AGENT_DEVICE_STATE_DIR="$PWD/.local/agent-device-ipad" npx e2e run tests/app-icon.e2e.ts --grep '^app icon picker shows both styles and twelve named currency tiles$'
```

The separate `accessibility`-tagged app-icon test changes text size and appearance after the picker is already open, checks adaptive tile width plus all twelve native names, and visually checks readable glyphs and the small contrasting selected badge. It targets only `CURRENCY_E2E_UDID` through `simctl ui`, validates the original settings before changing them, and restores both in `finally`. Run it on either owned phone or tablet profile with `npx e2e run tests/app-icon.e2e.ts --tag accessibility`. It does not change the selected icon.

## Limitations

- External links verify the exact native browser URL and return on iPhone. On iPad, Safari exposes only the hostname and the pinned driver cannot reliably copy the full address, so that browser check is blocked; Settings layout is covered separately. Website availability depends on the network.
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

Watch history loading (WATCH-04–05) uses the [maintained native Watch journey](../../../CurrencyWatch/README.md#history-loading-acceptance); its delayed range-state regression is in `CurrencyDetailsTests`. The iPhone E2E driver does not cover Watch.

Watch metal measurement (WATCH-14) uses the [maintained native Watch journey](../../../CurrencyWatch/README.md#metal-measurement-acceptance). The iPhone E2E driver does not cover Watch. Numerical, stale-draft and preference-sync regressions remain in the native unit test targets.

The `live-providers` journey is an explicit network acceptance check: `npx e2e run tests/widget-live-provider.e2e.ts`. It terminates the app, removes only the test-owned BTC/USD 1D cache, configures the installed History widget, and asserts the extension wrote positive minute-reference data spanning at least 23h45m before capturing its UI. Provider availability failures remain failures; no fabricated or daily history replaces 1D.

The live phone journeys use fixtures only to create completed onboarding and a saved currency selection. The general provider journey deletes the test-owned rate/1D/All caches and relaunches without `-CurrencyE2E`; network responses and persisted observations must then come from the production providers. Provider outages remain failures.

The weekly live journey removes only the test-owned rate and selected BTC weekly cache before launching production providers. It checks native hourly provenance, point count, coverage, gaps and USD-to-EUR conversion metadata, then verifies the visible 1W graph and unchanged saved observations after relaunch. Run `npm run test:e2e:extended -- tests/live-weekly-history.e2e.ts` on the owned iPhone. Within the same UTC hour, saved points, provenance and fetch time must stay unchanged; across an hourly boundary, the renewed cache must remain complete and move forward. Run it with `widget-history-sync` for weekly and shared-data changes.
