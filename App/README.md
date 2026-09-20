# Application

The executable composition root assembles live dependencies, owns scene presentation, and connects feature outputs to their destinations.

[Application modules](Modules) hold routing, foreground-refresh coordination, and appearance persistence. [Widgets](Widgets) is the separate extension; [integration tests](Tests) cover application wiring and shared resources.

Keep platform configuration and App Group assembly here. App and extension signing must agree with their entitlements. Build targets are declared in [Project.swift](../Project.swift).
