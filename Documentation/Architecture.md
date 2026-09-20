# Currency architecture

Currency is a modular SwiftUI app with a widget extension. Organize code around capabilities and the lifetime of their state. Keep business behavior independent of presentation so the app, widgets, tests, and previews can use the same rules with different dependencies.

This page defines how to make architecture decisions. Build manifests and source code describe the concrete modules and public APIs; [Decisions](Decisions.md) records product invariants and non-obvious constraints.

## Ownership before structure

The application assembles dependencies and coordinates the user journey. It owns startup decisions, scene navigation, deep links, and sequencing between features. Keep application components cohesive and name them for their responsibility. A high-level application model is a valid owner; a generic collection of services is not. Small wiring belongs near composition rather than in a module of its own.

A feature owns a user capability: its state, operations, validation, and local presentation. Give it focused inputs, dependencies, semantic outputs, and a UI entry. A feature can span several screens. Keep rules local until they have genuine shared meaning.

A domain owns reusable business concepts, capabilities, and authoritative state. Conversion, rate data, and widget configuration are examples. Networking, persistence, and Apple-platform implementations stay with the capability they serve, behind owned contracts. Reserve integrations for concrete third-party service or SDK wrappers.

Use the design system for general visual primitives: colors, typography, spacing, common controls, motion, and feedback. Reuse across screens alone does not make a component part of the design system.

## Dependencies and reusable UI

UI depends on logic; logic never depends on UI. Keep feature and domain logic independent of SwiftUI and environment lookup. Features never import sibling features or application modules. Domains never depend on features or the application. Keep the graph acyclic and declare direct dependencies explicitly in manifests.

A domain may expose a separate UI module for reusable presentation specific to that capability. Currency pickers and widget layouts belong with their business owner. Domain UI depends on domain logic and the design system; the design system has no business-domain dependencies.

Use the same production widget layouts in the extension and onboarding. Supply explicit state and action handlers: installed-widget interactions update coordinated storage, while tutorial interactions operate on temporary state. Rendering should not discover a global store or decide which persistence policy applies.

## Dependency injection

Prefer consumer-owned **structs of typed operation closures over custom service/repository protocols**. Supply only the capabilities a consumer needs, such as loading history or editing confirmed input. Preserve meaningful public protocols and required platform conformances; do not introduce a protocol per dependency.

The executable composition root chooses live implementations. SwiftUI environment values transport dependency structs to feature or domain UI entries, which pass them explicitly into model initializers. Models never read the environment. Intent handlers receive dependencies from extension composition without a SwiftUI environment.

Required entry wiring must fail visibly rather than selecting shared storage, live services, no-op behavior, or empty destinations implicitly. Intentionally inert presentation must be explicit. Public library convenience APIs can remain available without becoming hidden feature defaults.

Use the same dependency types for production, tests, previews, and harnesses. Define owned inputs, results and errors, actor isolation, sendability, and cancellation behavior. A single presentation action can use a closure directly. Exercise failures through the real dependency contract rather than adding a separate test-only behavior path.

Keep mutable UI-facing models `@MainActor` and use Observation. Models expose typed state and issues; UI owns localization, animation, accessibility, and feedback. For app-owned capabilities such as persisted appearance, composition adapts consumer-owned contracts instead of making features import the app implementation.

## Navigation and lifetime

Each scene owns its navigation and flow identities. Features emit semantic requests or outcomes; the application interprets them and presents the next feature. Keep feature-local navigation inside the feature. Returning results between flows requires explicit correlation and cancellation ownership.

A UI entry retains one model for one flow identity. Updating environment values does not replace an existing model or its captured dependencies. Start a new identity when a new flow is required.

Every async operation needs an owner, cancellation behavior, a repeated-action policy, and a stale-result rule. Ignore superseded results even if the underlying work does not cooperate with cancellation. End work on actual teardown; temporary disappearance is not necessarily the end of a flow.

Application-lifetime scheduling coordinates active scenes without multiplying automatic work. Features own user-initiated operations through the same domain capabilities. Keep progressive onboarding bootstrap and its recovery lifetime distinct from periodic refresh. Apply domain freshness rules in one place.

## Shared state and persistence

Give each persistent business record a clear domain or feature owner. Models hold working snapshots rather than competing authoritative stores. Separate transient visual state, editable drafts, and confirmed data.

The app and widget extension are concurrent writers. Mutate freshly loaded records under cross-process coordination, merge rate commits, and preserve lock ordering and generation checks. An in-process actor cannot coordinate two executables. Network work stays outside storage locks.

A successful UI outcome follows a successful commit. Onboarding drafts and widget demonstrations must not overwrite confirmed input before their intended commit. Save failures preserve the previous valid state and support recovery without repeating unrelated successful work.

Keep canonical widget configuration independent of the visible layout. Resizing must not discard hidden selections or input. Preserve the distinction between default synchronized widgets and custom independent input, and between a fixed currency and dynamic Local intent. Further persistence, privacy, and rate-provenance constraints live in [Decisions](Decisions.md).

## Validation at the owning boundary

Keep behavior tests beside their logic or UI owner and test cross-feature sequencing at the application boundary. Use fresh controlled dependencies. UI packages own their resources; test resource lookup in the executable and harness contexts that consume them.

Harnesses present production entries with selectable states and interactions. They validate isolated behavior; they do not establish integrated navigation, native widget identity, permission behavior, or accessibility. Validate those through the corresponding native journeys. Build and release procedures belong in [Development](Development.md).
