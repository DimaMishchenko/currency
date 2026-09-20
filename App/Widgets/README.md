# Widget extension

The WidgetKit executable adapts shared widget behavior into native configurations, intents, and timelines.

Keep reusable state and layouts in [Domain/Widgets](../../Domain/Widgets). Preserve installed-widget kinds, configuration identities, and intent encoding when changing adapters. The extension assembles its own live dependencies and shares coordinated storage with the app.

Adapter integration tests live in [App/Tests](../Tests/WidgetIntegrationTests). Signing and App Group configuration belong to this executable.
