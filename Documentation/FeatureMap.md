# Currency feature map

Inventory of the app’s implemented user capabilities, independent of any test framework. Use the stable IDs to define acceptance criteria, choose regression journeys, and identify missing coverage. An entry describes behavior to verify, not evidence that it has been verified on every platform.

Update this map when functionality changes. Keep test selection, execution commands and results in the relevant verification guides: [development](Development.md), [agent E2E](../Apps/Currency/Tests/E2E/README.md), [adaptive layouts](AdaptiveLayouts.md), and [localization](Localization.md). A test may cover only one representative path within a capability; list that scope explicitly.

## Onboarding

Owner: [Onboarding](../Features/Onboarding/Sources/Onboarding/OnboardingModel.swift), with application completion routing.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| ONB-01 | First launch: welcome, base currency, destination selection, finale | Completing setup opens the converter with the chosen source and destinations. |
| ONB-02 | Back navigation and interruption during setup | Choices survive Back/Continue and resuming an unfinished setup; each step remains usable. |
| ONB-03 | Optional location and widget setup steps | Setup can continue without opting in; selecting an optional flow returns to the appropriate onboarding step. The illustrated widget-gallery result uses the current native app icon, including its light/dark artwork; a first launch uses World Yen / Yuan and replay uses the user’s selection. |
| ONB-04 | Settings → Help → replay onboarding | Existing converter choices seed the replay; completion returns to the converter without losing the intended input. |

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
| RATE-01 | Initial bootstrap, foreground refresh, explicit rate refresh | Fawaz supplies daily fiat, crypto and metal rates. The phone, widgets, Watch and system actions share timestamped quotes. Foreground phone and widget refreshes reuse a shared 60-second current-quote window; Coin Metrics batches supported crypto quotes in one latest request, with a shared traffic budget, backoff and refresh lease. Failed refreshes retain the last valid current crypto quote; Fawaz daily rates remain the fallback when no current quote exists. Observation dates, approximate daily FX conversion and failures remain explicit. The phone Rates page formats retrieval, last-check and intraday observation times in the environment time zone, identified by one explicit Times label; daily Published dates retain the provider calendar day. |
| RATE-02 | Current rate/source information in converter, details and Settings | Currency-specific provenance, timestamps and warning states correspond to the snapshot used for conversion. Recoverable daily and crypto refresh fallbacks show the localized “Showing saved rates.” notice on phone and Watch; unavailable quotes and save failures retain their distinct states. |
| HIST-01 | Currency row → Details & history | Details retain the converter’s selected base as the comparison currency for distinct fiat, crypto and metal pairs; a self reference uses a distinct fiat fallback. The current quote and every history range use that same pair; supported crypto charts end at the shared latest quote endpoint; tiny positive reference values remain nonzero; opening details does not change saved selections. |
| HIST-02 | History range controls and chart | Frankfurter supplies daily fiat history through ECB or CBU in at most two batched range requests, with dated EUR cross-rates when needed. Fawaz supplies recent crypto/metal daily history and fiat fallback from March 2024. A failed Frankfurter refresh returns compatible saved Frankfurter history without a dated-request fanout. All combines bundled older Coin Metrics crypto and selected Frankfurter fiat monthly reference samples with Fawaz history; coverage depends on the pair. Coin Metrics supplies 1D crypto reference prices sampled locally and hourly 1W history for crypto pairs, with aligned crypto legs or explicitly approximate dated daily FX conversion. Weekly hourly windows must cover nearly seven days; incomplete or unavailable responses retain compatible saved history or fall back to daily history, with hourly retries and shared caches. The active history service retains a failed attempt’s one-hour retry delay even when a concurrent cache update leaves an older attempt saved. Fiat-only weeks and longer ranges retain daily/monthly sampling. Incomplete 24-hour windows remain unavailable or explicitly cached. Read and write validation rejects nonpositive/nonfinite values, unordered or duplicate daily/monthly observations, points after their fetch time, out-of-range dates, and incomplete intraday windows. Legitimate flat rates and publication gaps remain valid; no synthetic history is substituted. Legacy daily Fawaz fiat caches try the preferred source once, with valid saved data retained on failure. Concurrent history loads preserve valid fresh preferred daily fiat history over Fawaz fallback and retain newer fresh observations. The caller receives the retained series; invalid or stale records remain replaceable. |
| HIST-03 | Rate source disclosure | Phone Details identify the history provider and observation kind in the compact disclosure. Expanded content retains history start/end dates, the local Saved chart timestamp, conversion caveats and the crypto/fiat reference-data explanation. History disclosures omit redundant current-source summaries and Observed/Retrieved rows; unavailable-history fallback retains current-quote provenance without the source time-zone suffix. Watch Details retain their current/historical source information. Current crypto quotes identify their approximate FX input only when the requested pair actually needs that input. Direct crypto/USD and matching crypto/crypto normalization omit the approximation notice; actual mixed daily-FX conversions retain the rate, provider and publication date. Phone and Watch Details retain the requested comparison currency, including EUR/other fiat and crypto references; widgets retain their configured pair. History requests invert fiat/crypto legs when needed without changing the displayed pair or dated conversion metadata. Collapsing restores the compact disclosure. |
| HIST-04 | Close details or change range while loading | Returning preserves converter input; an earlier load does not replace the newly selected range or a dismissed flow. |
| HIST-05 | Select a point on the history chart | The selected point’s date and value are shown for the current pair/range. Phone minute/hourly history (1D and hourly 1W) uses the environment time zone for chart axes, selected timestamps and disclosed endpoint timestamps, with an explicit chart time-zone label. Daily/monthly reference dates preserve their provider calendar date across display time zones. |

## Preferences and Local currency

Owners: [Settings](../Features/Settings/Sources/Settings/SettingsModel.swift), AppearancePreferences, and [LocationOnboarding](../Features/LocationOnboarding/Sources/LocationOnboarding/LocationOnboardingModel.swift).

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| PREF-01 | Settings → Personalization → Theme: System, Light, Dark | The selected appearance applies and survives restart; System follows the platform appearance. |
| PREF-02 | Settings → Personalization → Accent color | The chosen supported accent applies and persists independently of theme. |
| PREF-03 | Settings → Personalization → Language → system Settings | iOS owns language selection; returning/relaunching uses localized UI and region formatting while currency identities remain stable. |
| PREF-04 | Settings → Rates, Sources, About → Acknowledgements, Privacy policy, Terms of use, Open source, version | Current information, artwork credits and testing-tool attribution are accessible; rate refresh has visible success/failure behavior and a short estimate disclaimer. Legal documents open their public repository pages; Open source opens the DimaMishchenko/currency repository. Returning preserves Settings. |
| PREF-05 | Settings → Metal measurement: Troy ounces, Grams, Kilograms | The selected weight unit persists and applies to metal conversion input/output, details, Calculator, Board, Mental Math and History widgets, widget showcase previews, and system actions. Metal amounts show their unit. Standard metal amount labels outside editing and reference rates target six significant digits, retain integer precision, omit trailing fractional zeros and keep tiny nonzero values visible; editable source amounts retain their full precision. Changing the unit preserves a metal source’s physical weight. Cash/Pocket weight presets retain their labeled units. |
| PREF-06 | Settings → About → creator footer: Email, Website, X | The centered portrait and “Made by Dimasike” identify the developer; interactive Liquid Glass contact buttons align with the Settings table edges, include Email/Website/X icons, and adapt to large text. Email uses the Feedback composer/fallback flow for dimasike.dev@gmail.com, Website opens dimasike.com, and X opens the dimasike_ profile. |
| PREF-07 | Settings → About → tap creator footer portrait | One tap rotates the coin through a full turn without dimming or tinting the portrait, briefly revealing a random SF Symbols currency face, then automatically restores the portrait. Each next currency differs from the previous choice. Reduce Motion uses a brief crossfade and also restores the portrait. |
| PREF-08 | Settings → Help → Feedback → choose Email or X | A single Feedback row opens an Email/X alert; its section footer invites bugs and ideas. Email presents the native mail composer when configured, otherwise opens the system mail handler or offers the address with Copy email when unavailable. X opens the dimasike_ profile. Cancelling or returning preserves Settings. |
| PREF-09 | Settings → Personalization → App icon → World or Grid → named currency tile | Supported hosts show two adaptive icon sections, each with Yen / Yuan (shared ¥ artwork), Euro, Pound, Rupee, Won and Bitcoin tiles paired with fixed USD artwork, and the platform’s selected icon. Selecting applies the Home Screen icon, shows progress and recoverable failure, and survives restart. Returning to the active app reconciles the platform selection. The tile layout updates live when Dynamic Type changes, keeping currency names readable and selection feedback bounded. Unsupported hosts hide the picker. |
| LOC-01 | Onboarding, Local row/picker, Settings → Location | Opt-in, system authorization, retry and skip paths work; denied, restricted, disabled, timeout and unavailable states offer the appropriate guidance. |
| LOC-02 | Local currency selected in app or widget configuration | A resolved location supplies the applicable currency; unresolved Local remains identifiable and directs the user to setup rather than presenting a false rate. |
| LOC-03 | Foreground/location refresh and return from system Settings | Permission/location changes reconcile across the app and shared widget data without discarding unrelated selections. |

## Widgets and widget discovery

Owners: [widget guide](../Features/WidgetOnboarding/Sources/WidgetOnboardingUI/OnboardingHomeScreen.swift), [widget bundle](../AppExtensions/CurrencyWidgets/Sources/CurrencyWidgets.swift), and Widgets domain. Installation/configuration happens through iOS; the in-app guide previews the capabilities and setup.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| WID-01 | Converter widget button or onboarding widget guide | Browse the gallery/collection, supported sizes and configuration previews; calculator/cash previews are interactive, motion can be paused, and Home/Lock Screen setup tutorials remain accessible. Navigation preserves app input. Tutorial gallery artwork reconciles the native icon on presentation and foreground return. |
| WID-02 | Calculator: medium/large, Default currency list | Follow the app’s currencies; keypad edits update shared app input and synchronized widgets. Medium shows the first four currencies; large shows up to eight. Rate-only refreshes preserve the active entered amount and update converted results; genuine app input changes still synchronize. Dense metal amounts show their measurement inline. |
| WID-03 | Calculator: Custom list and calculator instance | Configured currencies and editing state remain independent of Default/app input; separate calculator instances retain their own state. |
| WID-04 | Currency Board: small/medium/large | Display the configured base/targets and amount, with Default following the app and Custom retaining its selection. |
| WID-05 | Cash: medium | Configured base/comparison and cash presets/keypad produce the corresponding amounts, including Local setup/unavailable states where applicable. |
| WID-06 | Pocket Rate: small | Show a convenient reference amount and conversion for the configured pair. |
| WID-07 | Mental Math: small | Show the configured pair’s approximate mental-conversion rule and its accuracy information. |
| WID-08 | History: small/medium | Configured base/quote/range show history and its current, cached or unavailable state. Coin Metrics supplies supported crypto 1D reference history and hourly 1W history. Incomplete weekly coverage retains saved observations or daily fallback; fiat-only and longer ranges keep their existing sampling. Supported crypto History uses the same timestamped current quote as the converter and other widgets, while each graph and percentage retain the selected historical period. Longer ranges load their selected history without an additional 1D request. Current-quote requests share the normal 60-second refresh gate; historical caches retain their own range-specific lifetimes. WidgetKit controls actual timeline delivery and may defer updates. |
| WID-09 | Currency Icon: accessory circular Lock Screen widget | The configured currency symbol appears in the system accessory presentation. |
| WID-10 | System gallery, Edit Widget, taps, removal and reload | Installation/configuration produce the selected widget; intents execute in the real extension; removal works and shared data remains consistent. Tapping a widget with a valid saved quote context initially opens its immutable rendered quote; after about 1.5 seconds the scene adopts any newer shared quote. The widget context does not replace the authoritative rate cache or trigger a redundant fresh-cache fetch. Timeline persistence reads a bounded metadata index and writes one snapshot, so accumulated quote contexts do not multiply rendering memory; existing context links remain readable. |

The application accepts legacy `currency://convert` entry links and versioned converter routes. Valid saved quote contexts use `currency://widget?v=1&context=<UUID>`; expired or unavailable contexts fall back to current app quotes. See [widget links](../Domain/Widgets/Sources/WidgetsUI/WidgetComponents.swift), [Currency Icon](../AppExtensions/CurrencyWidgets/Sources/CurrencyWidget.swift), and [route handling](../Apps/Currency/Modules/CurrencyApplication/Sources/CurrencyScene.swift).

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

## Apple Watch

These capabilities target watchOS 26+. Ownership follows the Watch application composition, HomeWatchUI, CurrencyDetailsWatchUI and CurrencyWatchWidgets, reusing the Conversion, ExchangeRates and Widgets domains.

| ID | Capability / entry | Observable outcome |
| --- | --- | --- |
| WATCH-01 | Open the independent Watch app | The source amount and first conversion appear together on the small Watch; the app fetches rates directly and remains useful without an iPhone connection. |
| WATCH-02 | Tap source amount → decimal keypad | Digits, locale decimal separator and deletion edit a local draft; Done commits the amount and updates conversions, Cancel keeps the previous amount. The keypad fits without scrolling; there are no in-app 1/10/100 presets. |
| WATCH-03 | Source picker, Add currency and favorite row actions | Flag/icon currency choices update the source or destinations without duplicates. Favorite rows can become the base or be removed; selections and custom amount survive restart. |
| WATCH-04 | Favorite row → currency details/history | Show currency identity, inverse rate, selected history range/chart and the reference-rate note. Initial and subsequent range requests display a visible chart loader until history resolves, including revisiting an earlier range. Supported crypto pairs offer Coin Metrics 1D reference history; daily ranges use Fawaz. No provider/source sections, saved-rate label or standalone swap action are shown in the app. Metal conversion rates and history use the shared troy-ounce/gram/kilogram preference. |
| WATCH-05 | Refresh rates, offline and unavailable history | Explicit refresh preserves cached rates/history; loading, stale, missing and failed-refresh states remain distinguishable without claiming a successful fetch. |
| WATCH-06 | iPhone preferred-currency synchronization | Preferred currencies and metal measurement synchronize opportunistically; Watch base and physical metal amount remain local, and connectivity is not required for direct fetch/cache use. |
| WATCH-07 | Pocket Rate in Smart Stack | Configure source/comparison currencies, then use 1/10/100 and swap buttons to update the displayed pair/conversion. Setup has no amount field; taps on conversion content open the corresponding Watch route. |
| WATCH-14 | Metal measurement from iPhone settings | Follow the iPhone app’s troy-ounce/gram/kilogram setting through companion preference sync, without a Watch picker; conversions, details, history, widgets and Siri show that unit, and source-metal quantity is preserved. Cash keeps the same physical gram presets as the iPhone widget and translates routes into the selected app unit. |
| WATCH-08 | Currency Board and Favorite Pairs | Configure base, destinations and amount. Board aligns flag/code left and value right, with a bold source row; Favorite Pairs centers the flagged source above three flagged destination links. |
| WATCH-09 | History widget | Configured pair/range displays trend, period/change, current value and date, with explicit cached/unavailable behavior. Coin Metrics supplies supported crypto 1D reference history and hourly 1W history. Incomplete weekly coverage retains saved observations or daily fallback; fiat-only and longer ranges keep their existing sampling. The chart uses the space previously occupied by the daily-reference footer. |
| WATCH-10 | Know Your Cash widget | Configure currencies only; banknote or metal-weight buttons choose the amount and update conversion with the correct units. Opening the app preserves the displayed conversion semantics. |
| WATCH-11 | Mental Math widget | Display a simple rounded conversion rule for the configured pair without an error percentage. |
| WATCH-12 | Watch-face complications | Pocket Rate supports rectangular, circular, inline and corner families. Cash, Board, History and Mental Math support the first three; Favorite Pairs is rectangular only. Corner selection offers only Pocket Rate, with both compact values on the outer curve, one arrow, names/units inside and full values in accessibility. Verify slot fitting, including bottom-right 100-unit conversions. |
| WATCH-13 | Open Currency control and Watch Siri/Shortcuts | Control Center opens the Watch converter; existing conversion/rate operations run on Watch with exact amounts and actionable unavailable-rate outcomes. Spoken Siri and physical-device behavior require separate acceptance. |

Widgets are installed through the native Watch system surfaces; the app has no widget gallery, calculator or Currency Icon widget. Configuration previews and installed widgets retain selected currencies, amounts and history ranges; valid repeating-decimal conversions remain visible. History previews use cached data, while timelines can refresh. Native simulator configuration checks require development signing with a team identity, as documented in the PR's Watch README. Ordinary update labels are omitted from widgets while meaningful stale/unavailable status remains accessible. Physical-device battery/refresh behavior, reconnect/pairing transitions, exhaustive accessibility/content combinations and release signing remain separate acceptance checks.

## Cross-feature acceptance dimensions

Apply these to relevant journeys rather than duplicating every feature for every combination.

| Dimension | Expected behavior / detailed map |
| --- | --- |
| iPhone, iPad windows, Duo poses, orientation and resizing | Controls remain reachable and state survives layout changes. [Adaptive layouts](AdaptiveLayouts.md) records the geometry behavior and remaining native acceptance gaps. |
| Dynamic Type, VoiceOver, Reduce Motion and appearance | Content remains readable/actionable; labels describe controls and outcomes; transitions and overlays preserve state. |
| Languages, locale formatting, RTL and long text | App, widget and system-action text follows supported localization; numeric/currency identities remain correct. See [Localization](Localization.md). |
| Fresh/resumed/completed onboarding; cold/warm/background execution | The appropriate surface/state is restored, and unrelated persisted choices remain intact. |
| Live/cached/missing rates, offline/provider failure, permissions and shared storage | Each affected capability communicates its real state and preserves valid data. Controlled fixtures verify outcomes; separate checks establish real provider/system integration. |
