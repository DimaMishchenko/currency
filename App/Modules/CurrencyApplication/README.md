# CurrencyApplication

Application routing and per-scene flow state, independent of SwiftUI.

Translate feature outputs into application destinations here. Rendering and live dependency assembly stay in the executable; features do not import this module.

`ConversionAction` performs read-only external requests through explicit store, refresh, and clock closures. It snapshots selected destinations and Local once, shares the normal rate throttle, and never edits converter input. Exact request/result arithmetic stays in the Conversion domain.

`CurrencyRoute` validates versioned selected-content URLs. `CurrencyScene` owns pending onboarding routes and opens the existing details flow after composition validates current selection. Unselected or unavailable content does not change current navigation. Conversion actions return system-rendered values and dialogs; there is no conversion-result UI or request-opening route.
