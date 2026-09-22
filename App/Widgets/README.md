# Widget extension

The WidgetKit executable adapts shared widget behavior into native configurations, intents, and timelines.

Keep reusable state and layouts in [Domain/Widgets](../../Domain/Widgets). Preserve installed-widget kinds, configuration identities, and intent encoding when changing adapters. The extension assembles its own live dependencies and shares coordinated storage with the app.

Adapter integration tests live in [App/Tests](../Tests/WidgetIntegrationTests). Signing and App Group configuration belong to this executable.

## Widgets

- **Currency Calculator** — interactive conversion with a keypad.
- **Know Your Cash** — reference values for banknotes and metal weights.
- **Pocket Rate** — a useful reference amount for a currency pair.
- **History** — exchange-rate history and percentage change.
- **Mental Math** — a rounded rule for quick estimates.
- **Currency Board** — multiple conversion rates at a glance.
- **Currency Icon** — a currency symbol for the Lock Screen.
