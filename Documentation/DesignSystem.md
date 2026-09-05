# Shared UI styles

`Modules/CurrencySupport/Sources/AppStyle.swift` contains the app's shared styling definitions, available to both feature modules and widgets.

- Backgrounds use the platform system background; native lists, forms, bars, and glass keep their system surfaces.
- `AppAppearance` is observable state owned by `CurrencyApp` and injected into the SwiftUI environment. `accent` defaults to the adaptive system label color. Set `accent` to a color to update app tint, indicators, and charts; reset it to `Color(uiColor: .label)` to follow primary again. Feature screen hosts must inject `AppAppearance`.
- No settings UI or persistence is introduced yet. Widgets currently use the same system label default; future saved customization will need App Group storage and widget timeline reloads to cross the process boundary.
- `AppStyle.font` creates rounded system fonts from semantic text styles. Native controls retain their default fonts. The large amount displays use `@ScaledMetric` rather than fixed size caps. Currency counts retain a semantic monospaced font, and numeric values retain monospaced digits. Artwork and metal symbols keep their existing typography.
- Custom spacing uses 2, 4, 8, 12, 16, 32, and 48 pt (`xxs`, `xs`, `small`, `medium`, `large`, `section`, `spacious`). Zero denotes no gap. Native spacing remains automatic. Geometry such as 44 pt touch targets, icon sizes, chart dimensions, and content-width limits is separate from spacing.
- Currency rows stack the description and amount at accessibility Dynamic Type sizes. Numeric displays may still scale down to fit unusually long values.
