# Widget findings revision — 6 September 2026

This revision supersedes the compatibility plan in commit f16b736. The user explicitly requested removal of backward compatibility, a real Default setting, hidden identity, synchronized Default input, distinct Local entries, Default Board base alignment, solid permission UI and Allow Once handling. No new commit or push was requested.

## Changes

- Removed Pair registration/configuration, legacy Board enum/fixed list, input-key migration helpers/tests and obsolete related strings. There is one calculator gallery registration.
- Calculator mode now has an explicit nonoptional enum default of synchronized, displayed as Default. Old nil-mode inference was removed. The Calculator identity field is omitted from configuration summaries; the saved optional entity remains internal because App Intents metadata requires optional entity parameters.
- Default calculator edits share the app amount. Default and Custom keep separate files for a given identity, so mode switches preserve Custom input. Widget active selection and paging remain in widget storage; conversions bridge its active currency to the app source without changing the app's list. Custom actions write only their widget input file. Default Board reads app source, amount and list; Custom alone exposes separate base and amount controls.
- Local resolves to a distinct display identity, so fixed CZK and Local CZK remain separate. Both values convert with CZK rates, but only the dynamic entry receives a location badge. References also mark Local, including same-base comparisons. Local changes reconcile active state safely.
- Permission/setup cards use an opaque adaptive system fill. Small Pocket and Mental widgets retain their container background. Saved Local observations always identify themselves as saved; after one day a future timeline entry labels them last-known and links to the app.
- Allow Once expiration observed as Not Determined cancels work, clears the observation and reloads widgets. Foreground return does the same. A fresh Update requests permission again. Authorized transient failure retains last-known data. Guide translations explicitly explain manual updates, temporary authorization and one-day stale labeling.
- Discarded the identified automatic App/Info.plist key reorder and App/Widgets InfoPlist catalog churn.

## Validation

CurrencySupport and CurrencyIntegrationTests passed after adding Local duplicate/conversion, Default value isolation, and Allow Once expiration/late callback regressions. CurrencySupport passed at 20:54. The temporary source harness also exercised WidgetAction.perform: Default writes app input; two supplied Custom UUIDs keep distinct amounts; Custom leaves app input untouched; Board Default ignores an out-of-list configured base/amount and uses the app values. All five assertions passed. This is actual intent execution, but the supplied IDs do not validate OS identity allocation.

Extracted App Intents metadata confirms MultiSettings.list exports the synchronized default, its summary omits instance, and Board Default omits base/amount.

Supplemental simulator rendering: `/private/tmp/currency-widget-visual-harness/localdark.png` shows fixed CZK alongside badged Local CZK and the solid permission card, using exact source views and synthetic rates. It is not native WidgetKit tint/glass evidence.

The actual iPhone 17 Pro native widget gallery is empty, including system widgets. Screenshot: `/private/tmp/currency-17pro-gallery.png`. The same blocker was previously reproduced on isolated iOS 26.4/26.5 targets. No installed user widgets were removed to work around it.

Final CurrencyIntegrationTests passed at 20:57, including expiration during an active request; the full signed app/widget Simulator build passed. `git diff --check` passed. Installed and launched on iPhone 17 Pro. The isolated review simulator was shut down; the user simulator and its existing preview were left running. Changes remain uncommitted.

## Remaining limits

Automatic assignment/preservation of a different hidden UUID for each identical Custom widget, including duplicated configurations, is still unverified. Query-provided defaults can be cached by the system; supported WidgetKit APIs do not expose a per-placement identifier in the inspected SDK. Explicit-key independence and intent-action tests cannot establish native identity provisioning. There is no visible identity/reset setting in this revision. First Custom snapshot and editor Default presentation also need a functioning native editor to verify beyond metadata and source.

Allow Once reports authorizedWhenInUse while valid; it is not distinguishable from a persistent grant at that point. When the app is suspended or terminated, it cannot promise immediate detection of expiration. The cached display is therefore explicitly labelled saved, changes to last-known after one day, and offers foreground refresh. No arbitrary permission expiry timer is presented as an OS fact.

Apple sources: [requestWhenInUseAuthorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()) and [WidgetConfigurationIntent](https://developer.apple.com/documentation/appintents/widgetconfigurationintent). No widget-side location acquisition or broader permission request was introduced.

## 7 September: keypad, switching, picker and permission follow-up

Removed the fresh Saved location footer; retained the stale Last-known warning. Default keypad synchronization now remembers the exact published app amount/source/rate so conversion round trips do not reset each new digit. Internally converted Decimal values no longer pass through the 30-character configuration-text validator. A missing rate no longer forces the active tile back to the app source. Remembered synchronization is invalidated if configuration removes the active tile.

Selection changes write only the current widget file, read rates once, and no longer rewrite app input or reload other widgets. Numeric edits reload only calculator, Board and Quick Rate kinds. Timeline entry construction also reuses its rate snapshot.

Both Custom queries exclude already-selected IDs from suggestions/search and normalize duplicate IDs during entity resolution. Dependency initialization is explicit to avoid a Swift circular-initialization diagnostic. Live selected-array injection and native picker behavior still require a functioning widget editor; the direct query resolution tests cover duplicate ID normalization, not the system editor itself.

Permission cards now use an opaque raster fill with Image.widgetAccentedRenderingMode(.fullColor), because the normal Color fill can be transformed by Home Screen glass/tint rendering. The full-color source harness shows a solid panel and no fresh-location footer. Native glass appearance remains a device verification item.

Validation: full app/widget build and CurrencySupport tests passed. New regression tests type 12.3 across all six test currencies with persistence/reload after each key, external app edits, and missing-rate input. Actual WidgetAction.perform checks also passed for all six currencies, Default sharing, Custom isolation and duplicate entity IDs. Local selection handler timings were 2.4–24.1 ms (six samples); these exclude WidgetKit's system dispatch and rendering latency. Visual evidence: /private/tmp/currency-widget-visual-harness/localdark.png. No claim is made about measured on-device tap-to-render latency.


## 7 September: fixed calculator slots and resizing

Removed calculator paging and its intent command. Medium shows the first four currencies; large shows the first eight. Default reserves the last visible slot for Local when enabled. Custom keeps its configured order. Canonical codes and persistence keys remain independent of widget size. A hidden active currency projects its equivalent into the first convertible visible currency without saving that projection; expansion restores the original selection until the user interacts. Without a rate, saved input survives and the keypad remains disabled until a visible tile is selected. Keypad intents carry the projected currency and the expected hidden currency, so a stale keypad cannot reverse a newer selection.

Size-dependent native parameter summaries explain the limits in English. Built App Intents metadata contains the system.widgetFamily switch, Default/Custom branches, and Widgets localization table. Native editor rendering is still unverified because of the previously reproduced empty gallery.

Validation: CurrencySupport regression suite passed, including canonical resize persistence, equivalent-value projection, Local reservation at both limits, and missing-rate preservation. Full signed Simulator app/widget build passed. Actual source intent harness passed 25 checks, including Default/Custom typing after resize and stale keypad selection guards. Inspected `/private/tmp/currency-widget-visual-harness/resize.png`: the same saved 7 CZK input displays eight currencies on large and four on medium without paging or clipping. This is source-view rendering with synthetic rates, not native WidgetKit resizing/editor evidence.


## 7 September: interaction and Cash loading review

Removed invalidatableContent and numericText effects. Interactive buttons now use a label-only ButtonStyle so the pressed state does not fade their contents. Numeric content uses identity transitions; calculator/Cash animation suppression follows input changes, and Board follows the shared amount. Removed the blanket timestamp-based controls from WidgetSurface. Existing synchronized Decimal input, fixed 4/8 display, resize projection and stale-keypad selection guards remain. The internal synchronized intent parameter has a false default for archived controls that predate it.

Cash and the other timeline providers previously awaited the complete network refresh before returning a timeline. Widget refreshes now give each concurrently fetched provider a two-second deadline, cancel slow requests, and retain successful provider results. Fast providers return without waiting for the deadline. Empty-cache timelines request a retry after five minutes. Normal app refreshes omit the deadline and retain their existing behavior. Interactive mutations remain local and recent interactions skip network refresh. Explicit calculator-kind reloads remain necessary for sibling Default widgets to synchronize; WidgetKit also reloads the interacted widget automatically.

Fresh-context subagent review found and fixed a P2 in the first timeout implementation: cancelling the whole refresh discarded successful fiat results when crypto stalled. The final per-provider implementation passed follow-up review with no additional P1/P2 findings. CurrencySupport tests cover deadlines, cancellation, retained cached data, fast completion and fast-fiat/slow-crypto merging, alongside the earlier input/resize regressions. RateService regressions and signed device/Simulator builds passed. The actual-source intent harness passed 35 checks, including all CZK/XAU/EUR Cash presets and keeping Cash independent from app input. Inspected `/private/tmp/currency-widget-visual-harness/cash-reviewed.png`: fiat, missing-metal-rate and same-currency Cash views render without clipping.

The connected physical iPhone has one Currency app, com.dimasike.currency.d. The separate old production app found in the simulator does not explain the user's physical-device issue. The reviewed build was installed over the existing physical app and launched without deleting data or widget configurations. After testing the updated physical build, the user reported that interactions were much better and approved publication. This feedback supplements the source-view and automated checks; the specific cause of the earlier Cash loading failure was not conclusively reproduced.

Apple animation reference: https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities .
