# WidgetPresentation

Shared real SwiftUI widget layouts, presentation models, and command descriptions. The app and widget extension depend on this framework; source files are compiled once here.

`CalculatorLayout`, `CashView`, `AnchorView`, `BoardLayout`, and `QuickRateLayout` are the same views used by installed widgets and onboarding previews. `WidgetButtonRenderer` lets the extension provide AppIntent buttons and the app provide temporary preview buttons. Intent declarations, native configuration parameters, timeline scheduling, and persistence mutations remain in CurrencyWidgets.

`WidgetSpec` preserves canonical configuration independently of display paging. Preview callers supply location status explicitly to avoid reading shared state. The calculator's preview-only transition uses a single progress value; installed WidgetKit views use their exact family layout.

`Resources/WidgetPresentation.xcstrings` owns shared rendering text. Configuration metadata and intent text remain in Widgets.xcstrings.
