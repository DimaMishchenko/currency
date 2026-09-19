# CurrencySelectionUI

A reusable searchable currency picker for converter and onboarding features. `CurrencyChooser` accepts the current selection, app currencies, available rates, an optional supported-code filter, and a selection callback. Callers may also provide a fresh local observation, separate Local selection state, and a setup action. Selecting Local emits `WidgetSelection.localID` to preserve location intent rather than the resolved ISO code. Missing, stale, and failed observations open setup. It owns presentation and searching; callers own persistence.

The module depends on shared support and rate types, with no feature dependencies. Its English text lives in `Resources/CurrencySelection.xcstrings`.
