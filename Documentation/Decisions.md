# Decisions and boundaries

Document rationale and non-obvious constraints here. Architecture principles and DI rules live in [Architecture](Architecture.md); build manifests describe the concrete module graph. API contracts belong in code comments and regressions in tests. Keep completed reviews and validation diaries in Git history.

## Ownership and persistence

- Keep the rate core reusable and independent of UI. Currency-specific UI and localized copy belong to a separate domain UI module; App Group configuration and foreground scheduling remain app-owned. The app composes navigation so features remain independent.
- The app and widgets are concurrent writers. Mutate freshly loaded input through coordinated storage and merge rate commits; saving an in-memory snapshot can erase the other process's changes. Network work must stay outside the coordination lock.
- Default widgets share the app's monetary value; Custom input stays independent. Widget size must not change canonical configuration or discard hidden input. Treat persisted identifiers and widget configuration changes as compatibility decisions.
- Onboarding drafts and interactive previews must not overwrite confirmed app amounts or configured-widget state. Preview the production layouts with isolated actions. Save completion before leaving setup.

## Data and platform limits

- Use public, credential-free rate sources with offline fallbacks. Provider availability and terms can change; recheck them when changing integrations. Rates are indicative, not executable trading quotes.
- Publication, retrieval, and trade times have different meanings. Coinbase batch receipt time does not establish market freshness. Crypto history is USD-denominated; applying today's FX rate would misrepresent historical prices.
- WidgetKit controls execution and rendering. Timeline requests cannot guarantee refresh deadlines or calculator-like input latency. Tests with supplied widget IDs do not prove native per-placement identity.
- Local preserves location intent separately from a fixed ISO currency, even when both currently resolve to the same code. Permission requests require explicit user action; automatic app/widget lookups must never prompt. Persist only country, currency, and observation time; keep the map region in memory. Allow Once cannot be distinguished from persistent foreground authorization at grant time, so reconcile permission on return.

## Presentation

Use adaptive system surfaces and native controls, with restrained glass on controls. Accent emphasizes actions and selection; general content stays neutral. App appearance preferences do not recolor widgets. Use shared style and feedback APIs instead of feature-specific variants. Respect Dynamic Type, Reduce Motion, and scene inactivity; decorative motion and automatic refreshes stay silent.
