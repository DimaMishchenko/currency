# Test value and runtime audit

Baseline: `dbd63034403b997fa8a110d0298e3d10e3c81b36`, 2026-09-30. This audit applies the [test-audit value bar](https://github.com/openclaw/openclaw/blob/main/.agents/skills/test-audit/SKILL.md). The 20% removal budget is a ceiling, not a target. The repository has 353 Swift Testing declarations and 12 native XCTest cases before this change. Parameterized executions are counted separately by Xcode.

## Removed tests and remaining owners

All paths below are test files. No production API or test-support seam becomes unused through these cuts. Each cut is low risk because its observable contract has stronger remaining proof, or the asserted persistence path never receives the fixture being inspected. The full `CurrencyTests` scheme includes all keepers.

| Removed declaration and file | Failure actually detected; production owner and callers | Remaining proof | History |
| --- | --- | --- | --- |
| `HistoryTests.historyCachesAndFallsBackOffline`, `Domain/ExchangeRates/Tests/ExchangeRatesTests/HistoryTests.swift` | Immediate cache reuse and generic offline fallback. `HistoryService.load` is consumed by CurrencyDetails and HistoryTimeline. | `dailyWidgetCacheAvoidsRepeatedFetchesUntilExpiry`, `yearToDateRefreshCanFallBackWithinTheSameYear`, and `crossRateFailureUsesOnlyPreviousCompletePairCache` check exact expiry, complete data, and typed failure. | Architecture extraction `22f4bd3`; stronger widget cadence coverage added in `18b23b7`. |
| `HistoryWidgetTests.defaultPairTracksBaseAndFirstDisplayedDestination`, `Domain/Widgets/Tests/WidgetsTests/HistoryWidgetTests.swift` | Base/destination ordering and overrides. `HistoryWidgetPair` is consumed by `HistorySettings.resolvePair` and previews. | `HistoryWidgetAdapterTests.nativeDefaultsFollowAppAndOverridesAreIndependent` executes the same rules through shipping settings. | Both tests introduced in `18b23b7`. |
| `AppAppearanceTests.brightAndDarkFillsChooseOppositeLabelColors`, `Foundation/DesignSystem/Tests/DesignSystemTests/AppAppearanceTests.swift` | Exact black/white helper choices. `AppAccentLabel` consumes `accentForeground`. | `prominentLabelsHaveReadableContrastForEveryAccentAndAppearance` independently calculates contrast through the public boundary for every accent/appearance. | Both introduced in `22f4bd3`. |
| `OnboardingWidgetTests.previewEditsNeverWriteAppOrInstalledWidgetState`, `Features/WidgetOnboarding/Tests/WidgetOnboardingTests/OnboardingWidgetTests.swift` | Temporary input editing; persistence assertions inspect stores never supplied to the preview. `WidgetPreviewState` is consumed by WidgetPreview and onboarding showcase/configuration. | `editedPreviewUsesLiveStateWithExplicitCodesAndNewRates`, `calculatorPreviewUsesTemporaryCanonicalStateAcrossSizes`, and WidgetCommand/WidgetStore tests own temporary versus persistent reduction. Preview state has no store, path, or persistence key. | Added in `22f4bd3` during preview extraction. |
| `WidgetTests.staleLocationUsabilityIsSeparateFromPrivacyStatus`, `Domain/Widgets/Tests/WidgetsTests/WidgetTests.swift` | Freshness/usability and permission helper flags. Owners are WidgetLocation/WidgetLocationStatus, consumed by selection resolution and LocalCurrencyStore/controller. | `listOwnershipAndLocalPositionAreIndependentOfResolution`, `staleAndFailedObservationsAreExplicitlyMarked`, and `localCurrencyRequiresFreshSupportedCountry` exercise resolved behavior, every disallowed status, and exact expiry. | Initial widget overhaul `1e43d5c`, extracted in `22f4bd3`. |
| `WidgetTests.synchronizedValuePreservesWidgetSelectionAndCustomRemainsIndependent`, same WidgetTests file | Synchronized selection and value changes; custom assertion checks an untouched local value. `WidgetInput.synchronize` is consumed by SuiteTimeline/WidgetStore. | `defaultTypingSurvivesConversionAndTimelineReload` covers six currencies, persistence cycles, and subsequent app amount changes. | Added in `1e43d5c`. |
| `HomeEditingTests.removingActiveCurrencyClosesEditor`, `Features/Home/Tests/HomeTests/HomeEditingTests.swift` | Removing the edited destination closes editing and makes keypad input inert. `HomeModel.removeDestinations` is consumed by Home destination management. | `localEditorTracksSelectionRatherThanMatchingFixedCurrency` covers fixed/Local identity confusion; `missingRatePairClosesEditorWithoutMisreportingSaveFailure` and `concurrentlyRemovedEditingRowEndsEditingWithoutSaveError` cover inert input and unchanged storage. | Added in `22f4bd3`; stronger Local and concurrent-removal regressions followed. |

The tutorial Local preview test now executes once. Its previous five kinds supplied identical explicit codes and amount, bypassing every kind-dependent default. No distinct branch was exercised by the extra four invocations.

## Retained contracts

Keep cancellation, stale-result rejection, cross-process persistence/coordination, corrupt-record recovery, migrations, precision and rounding, provider wire parsing, catalog additions, resource/localization boundaries, and native App Intents transport/lifecycle. Static schema checks and round trips are independently meaningful storage contracts here. Refresh and bootstrap precedence remain separate because they use distinct merge implementations. Thirty-second fake providers normally terminate on cancellation; their configured delay is not elapsed suite runtime.

## Runtime evidence and root causes

Recent successful CI runs inspected: [36742396365](https://github.com/DimaMishchenko/currency/actions/runs/36742396365), [36696981366](https://github.com/DimaMishchenko/currency/actions/runs/36696981366), and [36647386827](https://github.com/DimaMishchenko/currency/actions/runs/36647386827). History suites take 6.4–12.3 seconds. Native test bodies take 90.0–209.7 seconds, with first-launch setup charged to the alphabetically first case. Compile, simulator boot, app install, and launch costs are separate from test-body time; deleting fast assertions will not remove those costs.

Local baseline uses an owned iPhone 18 Pro simulator on iOS 27.0 with isolated DerivedData and signed simulator binaries. Native baseline passes 12 cases in 77.173 seconds (102.542 seconds including build/runner). Unit baseline passes 352 declarations and fails one retained declaration: `cancellingHourlyRefreshPreservesTheLongRangeCache`. Its bounded readiness polling expires while unrelated mock requests occupy a process-global 150 ms CandlePacer. It remains covered and is repaired, not removed.

Move Coinbase candle pacing to `NetworkClient` immediately before the real URLSession transfer, after request coalescing. Both shipping clients (app timeout 30, widget timeout 10) retain process-wide pacing. Injected fixture clients and preview harnesses avoid transport delays through their existing HTTPClient boundary. Pagination still owns its three-page concurrency bound and structured cancellation. No public test-only bypass is added.

Bootstrap precedence uses its existing controlled provider to release the fallback after the primary update, replacing a 20 ms scheduling assumption and removing unconditional zero-duration sleeps. Native app readiness skips the absent-onboarding wait only when the primary onboarding button is absent and the Home toolbar exists. XCTest can expose the preloaded Home toolbar despite SwiftUI accessibility hiding, so onboarding takes priority and its disappearance is explicitly confirmed after completion. An initial candidate that relied on Home existence alone failed native validation and was corrected before delivery.

## Reproduce

Generate with `tuist install` and `tuist generate --no-open --cache-profile none`. Allocate a task-owned iOS 27.0 simulator and use its explicit UDID in both commands:

```sh
set -o pipefail
xcodebuild test -workspace Currency.xcworkspace -scheme CurrencyTests \
  -destination 'platform=iOS Simulator,id=<owned-UDID>' \
  -derivedDataPath <isolated-directory> -resultBundlePath <unit-result> \
  -collect-test-diagnostics never CODE_SIGN_IDENTITY=- 2>&1 | xcbeautify
xcodebuild test -workspace Currency.xcworkspace -scheme NativeIntentTests \
  -destination 'platform=iOS Simulator,id=<owned-UDID>' \
  -derivedDataPath <isolated-directory> -resultBundlePath <native-result> \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGN_IDENTITY=- 2>&1 | xcbeautify
```

Use `-only-testing:ExchangeRatesPackageTests` for pacing/history proof; `-only-testing:WidgetsPackageTests`, `-only-testing:WidgetIntegrationTests`, `-only-testing:ConversionPackageTests`, `-only-testing:LocalCurrencyPackageTests`, `-only-testing:HomePackageTests`, `-only-testing:DesignSystemPackageTests`, and `-only-testing:WidgetOnboardingPackageTests` cover the cut owners and siblings. Run strict Swift formatting, Python CI skip rules, shell syntax checks, and `git diff --check` before delivery.

## Validation results

The optimized full unit run passes all 347 declarations. Seven redundant declarations were removed and one independent transport contract was added, a net reduction of six (1.7%). Native coverage remains 12 cases. Test/support Swift LOC drops from 8,318 to 8,272 after the final review, including the new transport fixture proof. Production changes add 22 lines and remove 19, net +3, with no new public seam.

| Local history suite | Baseline seconds | Optimized seconds |
| --- | ---: | ---: |
| HistoryConcurrencyTests | 3.504 | 0.556 |
| HistoryTests | 7.394 | 0.542 |
| HistoryFailureTests | 8.022 | 0.541 |
| HistoryCrossRateTests | 10.196 | 0.547 |
| HistoryIntervalTests | 10.356, failed | 0.569, passed |

The slowest history suite improves by 94.5%. The new concrete transport suite takes 0.856 seconds and retains real scheduling proof. Replacing HTTPClient with its baseline source makes both independent 100 ms spacing assertions fail; restoring the optimized transport passes. The test uses the [Coinbase public request budget](https://docs.cdp.coinbase.com/exchange/rest-api/rate-limits), rather than pinning the implementation's extra 150 ms headroom. All requests are intercepted by URLProtocol.

These are local suite durations on the same owned simulator; cold compile and platform startup differences are not credited as test optimizations. Bootstrap signal control improves determinism, with no isolated speed claim. Strict Swift formatting, six CI skip-rule checks, all CI shell syntax checks, and diff whitespace checks pass.

The corrected native suite passes all 12 cases from a fresh app install in 71.264 seconds, versus 77.173 seconds on the local baseline. Total build/runner time is 85.745 seconds versus 102.542, but those totals include unequal compilation work. The native body improvement is 7.7% in this local pair; repeated CI runs are needed before treating it as a stable platform-wide gain.

Independent preservation and architecture review found no remaining P1/P2 findings after correcting the native readiness helper. The scoped comment audit removed eight non-exempt narrative lines across the changed files; public transport documentation remains. Raw baseline, failed readiness attempt, final runs, negative-control logs, and CI history are retained locally under ignored `.validation/test-audit/`.
