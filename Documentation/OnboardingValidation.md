# Onboarding implementation and validation

## 18 September 2026 polish

Current flow: Welcome → base currency → destination currencies → Home Screen → curated Calculator/Board/Cash previews → optional installation guide → Welcome to Currency → Get started → animated converter entrance. Later also goes to the finale. The finale is persisted; only Get started marks setup complete. A normal completed-app relaunch does not replay the entrance.

Dark onboarding surfaces now use raised system colors and subtle outlines. The shared picker places categories above a clipped list, fixing the reproduced iOS 27 overlap, and onboarding Search uses a native zoom presentation. Popular currencies use a shared fiat-led showcase with USD/EUR first (excluding the chosen base), plus BTC, ETH, gold and silver to introduce the supported categories. This is a product shortlist, not a trading-volume ranking.

Home Screen → Explore retains the outgoing scene identity and overlaps entrance/departure animations. Calculator resizing keeps a stable cell tree for different currency counts; board previews resize without the old content fade. Quick Rate remains available in the full collection's Lock Screen illustration. The guide menu has four leading-icon rows matching the supplied native reference. Widgets and Options have separate toolbar glass backgrounds.

Editable amounts group their integer digits immediately while retaining decimal precision and trailing zeros, in both the app and shared widget rendering. Keypad labels use a separate verbatim digit formatter, preserving `00`, `000`, and the decimal separator. WidgetKit still controls when an installed widget renders each intent result; this change does not promise zero system scheduling latency.

Validation used isolated iPhone simulators: iOS 27 for UI capture, iOS 26 for CurrencySupport and CurrencyIntegrationTests. CurrencySupport passes 41 tests (49 parameterized executions); CurrencyIntegrationTests passes 52 tests, including new locale/grouping/keypad and finale persistence/completion cases. Final Debug and Release simulator builds, strict formatting of changed Swift files, and `git diff --check` pass. The pre-change iOS 27 picker overlap was reproduced and the revised category/scroll layout inspected. The iOS 26 visual comparison could not be completed because input automation did not advance the app; model-test success is not a substitute for that comparison. Simulator text injection also did not enter a query in the iOS 27 search field, so typed-search interaction remains a manual check.

Light/dark surfaces, curated selection, interactive calculator, menu, finale, toolbar separation, Home Screen transition, calculator resize frames and converter entrance were inspected. Evidence and test bundles are in `/tmp/currency-polish-evidence`. Physical-device animation pacing, installed WidgetKit interactions, full VoiceOver and the accessibility settings matrix remain manual checks for this pass. No independent agent review was performed in this pass.

### Follow-up refinements

Base and destination scenes now arrive as one coherent group instead of staggered subviews. The 19 September revision also removes the independent delayed footer fade: scene, heading, subtitle and action text crossfade together on the same progress, using the Home Screen entrance scale/offset. The showcase order is Calculator, Board, Cash, with the caption “Explore even more widgets in the app.” The installation guide remains visible while its entire navigation stack crossfades directly into the finale. The selected finale design uses eight native flags around centered Welcome/to Currency text. The 19 September revision adds a staggered curved sweep with scale/blur settling, followed by a continuous 32-second orbit and gentle drift. The timeline pauses when inactive; Reduce Motion uses the stationary completed circle. The converter is mounted invisibly at the finale. The 19 September revision fixes both navigation roots to the same viewport, uses an opacity-only converter entrance, and prevents that entrance animation from propagating into its layout. Normal keypad animations remain enabled. The redundant amount cursor is removed, and Options stays available while editing; opening another sheet dismisses the keypad.

Quick Rate's rectangular mock now has an explicit 170×76-point allocation, aligned left below the clock. The Lock Screen illustration has enough height to avoid compressing the widget to a tiny mark. Both rectangular and inline layouts were visually inspected, including dark appearance. The shortened collection caption fits without clipping. The selected circle was inspected in light/dark and with Reduce Motion configured on the simulator. Debug/Release builds and all 52 integration tests pass for this follow-up; the unchanged support suite passed earlier in this session.

First-search-focus investigation: a five-second main-thread sample captured 415 samples in UIKit's `UIKeyboardTaskQueue.waitUntilAllTasksAreFinished`/condition-lock path and 1,300 idle samples, with no app filtering frame in that stall. A minimal native SwiftUI `.searchable` probe did not reproduce the same long wait after the keyboard was already warm. Evidence points to keyboard initialization, but does not establish an iOS 27-specific defect or a fix. Search now disables autocorrection and automatic capitalization because it accepts names and ISO codes; no hidden keyboard prewarming workaround was added. On-device cold-focus validation remains open. Profiles and motion captures are in `/tmp/currency-refinement-evidence`.

## Historical validation: 12 September 2026

The remainder records the earlier implementation in the isolated `a5b2/currency` worktree; the flow changes above supersede its completion and gallery behavior.

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

## 19 September motion follow-up

Debug and Release builds, changed-file Swift formatting, and diff checks pass. Simulator recordings `motion3.mp4` and `motion3-delivery.mp4` in `/tmp/currency-refinement-evidence` cover the curved intro, continuous orbit, early scene/footer transitions, converter crossfade, and animated keypad opening. The converter stays in place in the inspected entrance frames. These presentation-only changes do not modify the previously tested persistence models; model tests were not rerun for this follow-up. Physical-device pacing and the previously investigated first-keyboard stall remain outside the simulator visual result.

## Interactive welcome orbit

The ring mixes EUR/USD/JPY/GBP flags with BTC/ETH and gold/silver badges. Dragging around it grabs the rendered position, follows the shortest angular path across the ±π boundary, then releases with bounded angular momentum and exponential deceleration back to its ambient orbit. A second grab stops momentum without jumping. The central text stays fixed. Reduce Motion allows direct manipulation without a momentum tail; accessibility adjustment rotates by one item. Backgrounding cancels an active drag and preserves the paused clock.

Onboarding Back and Search no longer become disabled during scene transitions. Activating either settles the current presentation before performing its action, so controls remain functional as well as visually enabled.

Debug and Release simulator builds pass. All 56 integration tests pass, including four new motion tests covering boundary wrapping, grab/release continuity, both spin directions, and momentum decay. Changed Swift formatting and diff checks pass.

The mixed ring was rendered and inspected on iOS 27. Live drag and rapid toolbar-interruption checks remain unverified: touch injection stopped reaching both Currency and SpringBoard despite helper/device restarts; hardware Home still worked. The temporary simulator-only finale state was backed up and restored. Pure motion tests do not substitute for checking the drag gesture on a device.

## 19 September independent review

A fresh-context subagent reviewed the complete uncommitted change set and repeated review after fixes. Two P2 findings were resolved: a failed finale progress save now dismisses the installation guide to expose Retry save, and seven/eight-currency calculator previews interpolate toward the production compact layout, hiding currency codes while retaining 16-point icons, compact padding and stable cell identities. Final review reported no remaining actionable P1/P2 findings.

CurrencySupport passed again (41 tests; 49 parameterized executions). All 57 integration tests passed, including a new guide-finish save-failure/retry regression. Seven- and eight-currency preview and production layouts were rendered with SwiftUI on the isolated iOS 26 simulator and visually inspected for clipping. The temporary render harness was removed. Strict formatting, diff checks and main-checkout/worktree byte comparison passed. Evidence is under `/tmp/currency-refinement-evidence`: `ReviewSupport.xcresult`, `ReviewFinalIntegration.xcresult`, `ReviewRender.xcresult`, and `calculator-{7,8}-{true,false}.png` (true denotes the preview). Debug and Release final-build logs are `review-final-debug.log` and `review-final-release.log`.

This review does not close the previously documented live simulator-input limitation: flick gestures, rapid toolbar interaction and native guide dismissal after an injected storage failure still need an interactive device check. Physical-device animation pacing, cold keyboard focus and installed-widget behavior remain outside the automated regression result.
