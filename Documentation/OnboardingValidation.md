# Onboarding implementation and validation

Validated 12 September 2026 in the isolated `a5b2/currency` worktree.

## Delivered flow

Welcome with progressive rate bootstrap → base currency → destination currencies → interactive Home Screen illustration → six production widget previews → installation guide pushed onto the same navigation stack → converter. Later also completes onboarding; Options → Replay onboarding starts again with current app choices while preserving the entered amount.

The currency steps reuse the shared picker, native Back/Search controls, ordered selection and Popular carousels with More actions. The base code has a centered flag/name underneath; destinations retain their scrolling conversion preview. All six widget kinds and supported sizes use production preview views with isolated editable state. Single-size widgets reserve layout space without a redundant size label.

App onboarding and the continued widget guide share footer typography, spacing and primary-button weight. The guide illustration is vertically centered above that footer. Internal Back moves through guide steps; toolbar Back and the native edge gesture return to the same widget, size and edited value. Got it explicitly completes onboarding. Standalone guides keep their existing modal presentation.

The opening shows only the currency-symbol loader until a usable conversion has been persisted, then fades in the welcome composition. Valid cached rates bypass waiting. No artificial loading duration is introduced. Reduce Motion stops automatic motion; inactive scenes and open pickers suspend decoration and ticker movement. Accessibility layouts scroll, and stage changes reset their scroll position.

## Architecture and final review fixes

`OnboardingFeature` owns an internal observable `OnboardingModel` behind the public `OnboardingFlow` composition view. `CurrencySupport` owns the persisted progress value and store operations. The app composes feature views without feature-to-feature imports. `RateService.bootstrap` progressively delivers usable results while preserving the existing aggregate refresh API.

The model handles bounded bootstrap attempts, cancellation, stale/missing rates, ordered draft selection, persistence failures and completion. Preview amount 100 is independent of the app's entered amount. Confirmation preserves the latest app amount. Existing version-1 selection and completion records remain compatible with the added `baseCurrency` step.

Independent review covered architecture, correctness, simplicity, lifecycle and cleanup. Identified P2 issues were fixed and re-reviewed. These included keeping feature state internal, preserving scene identity and in-progress guide/preview state across text-size and geometry changes, and handling local-currency deep links at the stable app root. Dismissing the local-currency sheet refreshes the converter input. A final native check caught clipped pagination after an accessibility round trip. The scene now measures its actual viewport instead of retaining a footer-height measurement, eliminating the feedback loop while preserving scene identity.

Removed obsolete localization keys, unused parameters/branches and redundant preview wrappers. The temporary runtime scenario harness has been deleted. Debug and Release both use production providers and `CurrencyStore.shared`; former scenario/reset environment variables no longer inject fixtures. Controlled providers, clock/latency and storage-failure hooks remain only in meaningful regression tests and internal model test seams. Earlier fixture recordings are historical evidence, not the final runtime.

## Automated verification

| Check | Result |
| --- | --- |
| ExchangeRates package | 43 tests passed |
| CurrencySupport | 39 tests passed; 47 executions including parameterized cases |
| CurrencyIntegrationTests | 51 tests passed, including 23 onboarding model tests and interactive widget regressions |
| Currency app and widget Debug build | Passed after final layout correction |
| Currency app and widget Release simulator build | Passed after final layout correction |
| Strict Swift formatting for application/module/package sources | Passed |
| `git diff --check` | Passed |
| Independent review rounds | No remaining actionable P1/P2 reported |

Logs and test bundles are under `/private/tmp/currency-a5b2-onboarding/`: `SupportFinalStructure.xcresult`, `IntegrationFinalClean.xcresult`, `build-final-layout.log`, and `build-release-final-layout.log`. A broader lint check found two pre-existing long lines in `App/Tests/WidgetLocationTests.swift` (34 and 125); that unrelated file was left unchanged.

## Native regression evidence

Curated media is under `/Users/dimamishchenko/.codex/visualizations/2026/09/10/01a08b2c-48a1-7fe3-96d2-7f3ca551c633/onboarding/`.

The dedicated devices are iPhone 17 Pro / iOS 26.5 (`DC2004FA-7CB6-4332-BF1E-E4A33EB4D268`, 402×874 points) and iPhone SE 3 / iOS 26.5 (`22E12947-3712-4E3C-86E7-F2239BDE9323`, 375×667 points). Native scenario setup modifies only these simulators' backed-up app containers; no scenario code remains in the app.

- Normal production-provider launch and cached rates; loader/welcome handoff.
- Both currency steps, native toolbar search, both carousel endpoints/More pickers, ordered selection and Back.
- All six widget kinds, size changes, editable Calculator/Cash and guide completion.
- Matching app/guide footer frames on both devices: primary `(24, 734, 354, 62)` on the main phone and `(24, 561, 327, 62)` on the compact phone.
- Guide step retained across live accessibility text changes and rotation; Large Calculator value 7 and family retained on return (`final-viewport-large-retained.png`).
- Complete page indicators after the final layout correction (`final-viewport-large-direct.png`).
- Local-currency deep link during an unfinished guide; manual save returns to the same step (`final-review-local-link-resumed.png`). From the converter, a newly saved AED appears immediately (`final-review-local-converter.png`).
- Local-currency links received behind an open Widgets sheet remain queued and present when that sheet closes.
- Compact layouts, larger text, maximum accessibility scrolling, dark appearance and Reduce Motion. Earlier native captures also cover increased contrast, reduced transparency and forced RTL.
- Failure/retry, empty selection, completion/relaunch and replay were exercised during development and remain covered by automated regression tests after removal of the runtime harness.

## Final walkthrough

The replacement `currency-onboarding-full-2026-09-12.mp4` is recorded from the final Debug app with production providers. It covers the opening, both currency steps and carousel endpoints, pickers, interactive Home Screen, every widget kind, sizes, guide Back/return/reopen, all Home Screen guide steps and completion. The final file is 3:57 (236.827 seconds), H.264, 1206×2622, 101,744,411 bytes. Production rate readiness was observed after 2.22 seconds. Opening and stage/guide transitions were sampled at 10 fps in `final-production-opening.png`, `final-production-stage-*.png`, and `final-production-motion-*.png`. The full overview is `final-production-full-contact.png`. SHA-256: `95ff146bbf3cbeb3fa74087794c8da25de35f97459311ecd2c84d9b256a613f3`. The replacement in iCloud Drive/codex was checked byte-for-byte against this file; iCloud confirmed Uploaded true and Uploading false. Independent visual review of the final opening, app-stage and guide-transition frames found no required material fixes.

## Platform limits

The simulator and sampled video frames do not establish physical-device frame pacing, thermal behavior, full spoken VoiceOver usability or native WidgetKit installation. Gallery availability and OS-assigned widget identity remain device checks. The Home Screen shown during onboarding is an illustration. English fallback and RTL layout were checked; no Arabic translation is claimed.
