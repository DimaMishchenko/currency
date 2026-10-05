# Currency feature map

Inventory of the app’s implemented user capabilities, independent of any test framework. Use the stable IDs to define acceptance criteria, choose regression journeys, and identify missing coverage. An entry describes behavior to verify, not evidence that it has been verified on every platform.

Update this map when functionality changes. Keep test selection, execution commands and results in the relevant verification guides: [development](Development.md), [agent E2E](../Apps/Currency/Tests/E2E/README.md), [adaptive layouts](AdaptiveLayouts.md), and [localization](Localization.md). A test may cover only one representative path within a capability; list that scope explicitly.

## Onboarding

Owner: [Onboarding](../Features/Onboarding/Sources/Onboarding/OnboardingModel.swift), with application completion routing.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| ONB-01 | First launch: welcome, base currency, destination selection, finale | Completing setup opens the converter with the chosen source and destinations. |
| ONB-02 | Back navigation and interruption during setup | Choices survive Back/Continue and resuming an unfinished setup; each step remains usable. |
| ONB-03 | Optional location and widget setup steps | Setup can continue without opting in; selecting an optional flow returns to the appropriate onboarding step. |
| ONB-04 | Settings → replay onboarding | Existing converter choices seed the replay; completion returns to the converter without losing the intended input. |

## Converter and currency selection

Owner: [Home](../Features/Home/Sources/Home/HomeModel.swift), [converter UI](../Features/Home/Sources/HomeUI/HomeScreen.swift), and the Conversion domain.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| CONV-01 | Source or destination amount → calculator keypad | Editing an available currency amount updates the other currency amounts consistently. |
| CONV-02 | Source currency picker | Searching/selecting a supported currency changes the source while maintaining a valid converter selection. |
| CONV-03 | Add currency and Options → manage currencies | Search localized names, codes and aliases; browse selected currencies, fiat, crypto and metals; add/remove/reorder destinations, preserving their saved order and avoiding duplicate selections. |
| CONV-04 | Keypad digits, decimal separator, deletion and Done | Editing follows the supported amount grammar; completion commits the result; unavailable conversions cannot be edited as valid amounts. |
| CONV-05 | App restart, foreground return, shared widget changes | Saved input is restored. Unchanged shared input preserves valid editing; changed shared source/amount ends editing and displays the authoritative input. |
| CONV-06 | Currency row context menu → Copy amount | The selected row’s formatted amount reaches the clipboard. |
| CONV-07 | Context menu and converter discovery tips | Details/history, removal, and widget entry points open the appropriate surface; contextual tips respect prior discovery. |

## Rates and history

Owners: ExchangeRates domain, [CurrencyDetails](../Features/CurrencyDetails/Sources/CurrencyDetails/CurrencyDetailsModel.swift), and application refresh composition.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| RATE-01 | Initial bootstrap, foreground refresh, explicit rate refresh | Available rates update conversion; loading, provider failures, missing rates and cached fallback are represented without fabricating a successful fetch. |
| RATE-02 | Current rate/source information in converter, details and Settings | Currency-specific provenance, timestamps and warning states correspond to the snapshot used for conversion. |
| HIST-01 | Currency row → Details & history | The requested currency and its applicable reference pair are shown; opening details does not change saved selections. |
| HIST-02 | History range controls and chart | Available 1D, 1W, 1M, 3M, 1Y, YTD and All ranges load the matching series. Unsupported pairs, missing intraday data, unavailable history and cached series have explicit states. |
| HIST-03 | Rate source disclosure | Expanded content explains current/historical sources and reference-rate gaps; collapsing restores the compact disclosure. |
| HIST-04 | Close details or change range while loading | Returning preserves converter input; an earlier load does not replace the newly selected range or a dismissed flow. |
| HIST-05 | Select a point on the history chart | The selected point’s date and value are shown for the current pair/range. |

## Preferences and Local currency

Owners: [Settings](../Features/Settings/Sources/Settings/SettingsModel.swift), AppearancePreferences, and [LocationOnboarding](../Features/LocationOnboarding/Sources/LocationOnboarding/LocationOnboardingModel.swift).

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| PREF-01 | Settings → Theme: System, Light, Dark | The selected appearance applies and survives restart; System follows the platform appearance. |
| PREF-02 | Settings → Accent color | The chosen supported accent applies and persists independently of theme. |
| PREF-03 | Settings → Language → system Settings | iOS owns language selection; returning/relaunching uses localized UI and region formatting while currency identities remain stable. |
| PREF-04 | Settings → Rates, Sources, Acknowledgements, version | Current information, artwork credits and testing-tool attribution are accessible; rate refresh has visible success/failure behavior. |
| PREF-05 | Settings → Metal measurement: Troy ounces, Grams, Kilograms | The selected weight unit persists and applies to metal conversion input/output, details, Calculator, Board, Mental Math and History widgets, widget showcase previews, and system actions. Metal amounts show their unit; changing the unit preserves a metal source’s physical weight. Cash/Pocket weight presets retain their labeled units. |
| LOC-01 | Onboarding, Local row/picker, Settings → Location | Opt-in, system authorization, retry and skip paths work; denied, restricted, disabled, timeout and unavailable states offer the appropriate guidance. |
| LOC-02 | Local currency selected in app or widget configuration | A resolved location supplies the applicable currency; unresolved Local remains identifiable and directs the user to setup rather than presenting a false rate. |
| LOC-03 | Foreground/location refresh and return from system Settings | Permission/location changes reconcile across the app and shared widget data without discarding unrelated selections. |

Send feedback is currently displayed as “Coming soon”; it has no submission action. It is not an implemented feedback flow.

## Widgets and widget discovery

Owners: [widget guide](../Features/WidgetOnboarding/Sources/WidgetOnboardingUI/OnboardingHomeScreen.swift), [widget bundle](../AppExtensions/CurrencyWidgets/Sources/CurrencyWidgets.swift), and Widgets domain. Installation/configuration happens through iOS; the in-app guide previews the capabilities and setup.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| WID-01 | Converter widget button or onboarding widget guide | Browse the gallery/collection, supported sizes and configuration previews; calculator/cash previews are interactive, motion can be paused, and Home/Lock Screen setup tutorials remain accessible. Navigation preserves app input. |
| WID-02 | Calculator: medium/large, Default currency list | Follow the app’s currencies; keypad edits update shared app input and synchronized widgets. Medium shows the first four currencies; large shows up to eight. |
| WID-03 | Calculator: Custom list and calculator instance | Configured currencies and editing state remain independent of Default/app input; separate calculator instances retain their own state. |
| WID-04 | Currency Board: small/medium/large | Display the configured base/targets and amount, with Default following the app and Custom retaining its selection. |
| WID-05 | Cash: medium | Configured base/comparison and cash presets/keypad produce the corresponding amounts, including Local setup/unavailable states where applicable. |
| WID-06 | Pocket Rate: small | Show a convenient reference amount and conversion for the configured pair. |
| WID-07 | Mental Math: small | Show the configured pair’s approximate mental-conversion rule and its accuracy information. |
| WID-08 | History: small/medium | Configured base/quote/range show history and its current, cached or unavailable state. |
| WID-09 | Currency Icon: accessory circular Lock Screen widget | The configured currency symbol appears in the system accessory presentation. |
| WID-10 | System gallery, Edit Widget, taps, removal and reload | Installation/configuration produce the selected widget; intents execute in the real extension; removal works and shared data remains consistent. |

Some widget entry links currently emit legacy `currency://convert`, while the application route parser accepts the versioned converter route below. Converter opening from those links requires correction/validation; it is not established by rendering a widget. See [widget links](../Domain/Widgets/Sources/WidgetsUI/WidgetComponents.swift), [Currency Icon](../AppExtensions/CurrencyWidgets/Sources/CurrencyWidget.swift), and [route handling](../Apps/Currency/Modules/CurrencyApplication/Sources/CurrencyScene.swift).

## System actions and external navigation

Owners: [SystemActions](../Apps/Currency/App/Sources/SystemActions), [CurrencyRoute](../Apps/Currency/Modules/CurrencyApplication/Sources/CurrencyRoute.swift), and application scene routing.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| SYS-01 | Shortcuts/App Intents → Convert amount | Resolve source/destination and amount; return structured exact conversion, readable text/dialog, monetary value or actionable error/status without requiring foreground UI. |
| SYS-02 | Convert to my currencies / Convert to Local | Return saved destinations in order or the resolved Local result; unavailable setup/rates have actionable outcomes. |
| SYS-03 | Check exchange rate; chain conversion results | Return the requested rate and reusable exact output without losing decimal precision. |
| SYS-04 | Entity queries, Spotlight indexing, visible entity annotations | Supported catalog currencies can be found; annotations reflect visible content. System presentation/ranking and Siri interpretation need their own acceptance checks. |
| SYS-05 | Open currency details intent; `currency://currency?v=1&id=USD` | Cold/warm opening reaches the requested existing details without changing saved selections; an onboarding app defers supported content until completion. |
| SYS-06 | `currency://converter?v=1`, `currency://local-currency` | Open the converter or location setup respectively; malformed/unsupported versioned content URLs are rejected. |
| SYS-07 | Published App Shortcut phrases and system discovery | Currency actions can be discovered/configured/run through the actual system surface. Siri/device behavior is distinct from native intent contract execution. |

## Cross-feature acceptance dimensions

Apply these to relevant journeys rather than duplicating every feature for every combination.

| Dimension | Expected behavior / detailed map |
| --- | --- |
| iPhone, iPad windows, Duo poses, orientation and resizing | Controls remain reachable and state survives layout changes. [Adaptive layouts](AdaptiveLayouts.md) records the geometry behavior and remaining native acceptance gaps. |
| Dynamic Type, VoiceOver, Reduce Motion and appearance | Content remains readable/actionable; labels describe controls and outcomes; transitions and overlays preserve state. |
| Languages, locale formatting, RTL and long text | App, widget and system-action text follows supported localization; numeric/currency identities remain correct. See [Localization](Localization.md). |
| Fresh/resumed/completed onboarding; cold/warm/background execution | The appropriate surface/state is restored, and unrelated persisted choices remain intact. |
| Live/cached/missing rates, offline/provider failure, permissions and shared storage | Each affected capability communicates its real state and preserves valid data. Controlled fixtures verify outcomes; separate checks establish real provider/system integration. |
