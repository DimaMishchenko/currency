# Widget onboarding implementation and validation

Validated on 8 September 2026 in the isolated `2174/currency` worktree.

## Delivered

- Moving showcase with mixed widget sizes, opposite column motion, pause control, and Reduce Motion support.
- A collection and interactive playground covering six widget kinds and ten supported kind/size combinations: Calculator medium/large; Cash medium; Pocket small; Mental Math small; Board small/medium/large; Quick Rate inline/rectangular.
- Real widget presentation views with temporary preview actions and labeled sample rates. Calculator entry, currency switching, cash presets, reset, and size changes do not write app or configured-widget state.
- Home Screen add and edit walkthroughs with assembled native-style illustrations, Next, Back, Replay, dismissal, and editable practice settings. Calculator Default/Custom, optional Local currency, pair selection, Board base/amount, and currency-list editing reflect their actual configuration semantics.
- Distinct inline and rectangular Lock Screen walkthroughs. Picker illustrations were compared with native iOS UI, including the inline grouped Choose Widget picker and rectangular app-detail picker.
- Independently accessible local-currency onboarding via `currency://local-currency`. Before authorization, it shows an abstract currency illustration. An explicit request presents native permission UI, performs a foreground one-shot lookup, then reveals a broad region map and currency badge. Manual selection, denial, failed lookup, cache removal, retry, and dismissal are handled separately.
- Accessible scrolling layouts at large text sizes, adaptive light/dark colors, native controls, typed framework-local strings, and public API documentation.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `WidgetPresentation` | Shared real widget layouts and value-based commands. The app supplies in-memory buttons; the extension supplies AppIntent buttons. |
| `WidgetOnboardingFeature` | Showcase, collection, playground, practice state, and installation/editing tutorials. The host injects the local-currency destination. |
| `LocalCurrencyOnboardingFeature` | Permission explanation, location state machine, result presentation, manual selection, and authorization reconciliation. |
| `CurrencySelectionUI` | Reusable currency chooser shared by the converter and onboarding features. |
| `ConverterFeature` | Presents the feature entry points and routes the deep link. |

Features do not import one another. Widget extension configuration and AppIntent identities remain in the extension; view extraction does not redefine those identities in a framework. Canonical currency lists remain distinct from display-limited lists.

## Automated checks

| Check | Result | Evidence |
| --- | --- | --- |
| Signed simulator app and extension build | Passed, including final accessibility layout and metadata wording | `.validation/onboarding/build-final-v25.log` |
| Onboarding, location, and localization tests | 19 passed across 3 suites | `.validation/onboarding/tests-final-v23.log` |
| CurrencySupport regression tests | 39 passed across 5 suites | `.validation/onboarding/tests-support.log` |
| ExchangeRates package tests | 37 passed across 11 suites during this work session | `swift test` |
| Strict Swift formatting lint | Passed across Sources, Modules, App/Sources, Widgets/Sources | `swift format lint --recursive --strict Sources Modules App/Sources Widgets/Sources` |
| Public DocC analysis | Passed for arm64 and x86_64 simulator builds with warnings treated as errors | `.validation/onboarding/docbuild-final.log` |
| Patch whitespace validation | Passed | `git diff --check` |
| Independent code review | No remaining actionable P1/P2 findings in the onboarding changes, including final deltas | Fresh-context reviewer, read-only review |
| Critical visual/motion review | Accepted final showcase motion, Board resize, tutorial scaling, location result, and both Lock Screen picker illustrations | Fresh-context critical designer inspected captures and video frames |

The focused test run precedes the final text-only system description and the accessibility Back/Replay layout adjustment. Those final changes were build-checked, reviewed, and the accessibility change was exercised in the simulator. Existing state-machine and persistence tests were not represented as proof of native widget-instance behavior.

## Native and visual verification

All evidence below is local to `.validation/onboarding/`, which is ignored by Git. The two dedicated simulators were iPhone 17 Pro / iOS 26.5 (`0F04142C-A6F5-4BC9-ADBC-AA6611E525AD`, port 3274) and iPhone SE 3 / iOS 27.0 (`A4630B03-040B-452D-9562-7F9A1A9782A3`, port 3275).

| Scenario | Observed result | Evidence files |
| --- | --- | --- |
| Preview calculator | Entering 75 produces EUR 75 / USD 81; currency switching, decimal entry, resize, and reset work | `onboarding-journey-final.mp4`, `calculator-75.png` |
| Preview persistence isolation | App amount remained 1; app input and configured-widget files were unchanged before/after preview interaction | `preview-store-before.json`, `preview-store-after.json` |
| Cash, Pocket, Mental Math | Presets and reset work; reference conversions and labels remain legible | `pocket-v16.png`, `mental-v19.png` |
| Board sizes and transitions | Small, medium, and large rows fit. Fade/resize/reveal avoids the prior overlapping-grid transition | `board-family-contact-v19.jpg`, `board-resize-v21.mp4`, `board-shrink-frames-v21.jpg` |
| Practice configuration | Pair comparison selection updates the preview; Board base/amount editing works; custom list can add/remove Local and preserves at least one currency | `tutorial-pair-gbp-v16.png`, `tutorial-board-default-v21.png` |
| Native Home Screen | Currency appears in the system gallery; calculator can be placed; native Default/Custom editor loads | `native-currency-gallery-ios27.png`, `native-calculator-home-ios27.png`, `native-edit-default-ready-ios27.png`, `native-edit-custom-ios27.png` |
| Native Lock Screen | Inline and rectangular Quick Rate widgets were installed and render real conversion values | `native-lock-widgets-live-ios27.png`, `native-lock-inline-picker-ios27.png`, `native-lock-rectangle-picker-ios27.png` |
| Final Lock Screen tutorials | Distinct picker structures and inline date placement match observed native UI | `tutorial-lock-inline-final-v23.png`, `tutorial-lock-rect-final-v23.png`, `quick-inline-final-v23.png` |
| Approximate location | Real Allow Once prompt followed by synthetic Prague lookup, Czechia map, and CZK result; no exact-location dot | `local-currency-journey-final.mp4`, `local-introduction-final.png`, `local-ready-final.png` |
| Recovery and routing | Denial exposes Settings/manual actions; manual CHF selection reaches app; cache removal returns to introduction; direct URL opens over an existing details sheet and closes back to it | `local-denied-compact-v18.png`, state-machine tests, native UI interaction |
| Reduce Motion | Native setting enabled; showcase and tutorial image crops remained pixel-identical across captures about 15 seconds apart; navigation still worked | `showcase-reduce-motion-v19-a.png`, `showcase-reduce-motion-v19-b.png`, `tutorial-reduce-motion-v19-a.png`, `tutorial-reduce-motion-v19-b.png` |
| Maximum text size and dark mode | On SE at AX5, content and actions scroll; Next returns to the start of the next step; Back/Replay stack without broken words | `local-compact-maxtext-v18-top.png`, `local-compact-maxtext-v18-actions.png`, `tutorial-maxtext-final-next.png`, `tutorial-maxtext-actions-fixed-v25.png` |

The showcase recording was inspected around its repeat boundary and the Board recording around both size changes. No visible seam, teleport, clipping, or overlapping rows remained in those inspected sequences. Recordings are visual evidence, not a device-wide performance benchmark. No physical-device or fully spoken VoiceOver session was performed; accessibility labels and native accessibility-tree state were inspected.

## Known limitations and separate finding

**Existing native calculator identity defect (P1):** on the installed Home Screen calculator, pressing 7 then 5 can produce 5 instead of 75. Native testing created two state files, one per key press. Source review traced this to the existing hidden calculator-instance parameter and `CalculatorInstanceQuery.defaultResult()` generating a fresh UUID. The same design exists in the starting revision; it is not introduced by presentation extraction. A stable identifier explicitly supplied by a harness does not prove automatic per-placement identity. No instance/profile redesign was made as part of onboarding. Native calculator typing and independence therefore remain unaccepted despite passing in-app preview behavior.

On the iOS 27 simulator, `UIApplication.openSettingsURLString` opened the Settings root rather than the app-specific page. Return/reconciliation logic is covered, but an app-specific native Settings landing was not demonstrated there.

The iOS 26.5 simulator's widget gallery did not expose Currency during earlier testing. Native gallery, editor, and Lock Screen acceptance was obtained on the dedicated iOS 27 simulator. Wallpaper controls vary by OS; the guide uses generic placement language and an illustrative Home/Lock Screen.

Location uses synthetic simulator coordinates for validation. Successful lookup saves country, currency, and observation time; the broad map region remains in memory. It performs no background or continuous lookup. Active Allow Once authorization cannot be distinguished from persistent foreground authorization by the app; later reconciliation handles expiration. Tests cover unavailable, cancellation, late-result, and authorization paths that would otherwise depend on system/network timing.

## Reviewable media

- [Onboarding preview, 40 seconds](../.validation/onboarding/Preview.mp4): actual showcase → collection → calculator interaction → resize → Home Screen tutorial.
- [Local currency, 18 seconds](../.validation/onboarding/LocalCurrency.mp4): actual explanation → approximate permission prompt → CZK map result; idle prompt time is trimmed.
- [Continuous showcase recording](../.validation/onboarding/showcase-final-v21.mp4).
- [Final local-currency result](../.validation/onboarding/local-ready-final.png).
- [Real installed Lock Screen widgets](../.validation/onboarding/native-lock-widgets-live-ios27.png).

Share videos are resized exports from simulator recordings. Export frame rate is not a claim about rendering performance. Raw recordings and contact sheets remain alongside them.
