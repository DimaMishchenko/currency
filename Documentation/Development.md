# Development

## Working locally

Use Xcode and Tuist. Toolchain and deployment requirements live in the manifests.

Run `tuist generate --no-open` after changing manifests or dependencies, then open `Currency.xcworkspace`. Changes inside existing buildable folders do not require regeneration.

- `Currency` builds the app and widget extension.
- `CurrencyTests` runs the combined test suite; `swift test` runs the standalone rate-core tests.
- `CurrencyHarnesses` builds the isolated development apps. Module READMEs list their harness launch arguments.

For command-line Xcode builds, use `set -o pipefail` and pipe combined output through `xcbeautify`. Use a separate simulator and derived-data directory for parallel work.

Before delivery, run the relevant tests, check affected UI, and verify formatting with `swift format lint --recursive --strict App Domain Features DesignSystem` and `git diff --check`. Outstanding device and release checks live in [GitHub Issues](https://github.com/DimaMishchenko/currency/issues?q=is%3Aissue+is%3Aopen+label%3Averification).

## Conventions

Keep signing enabled when validating shared App Group storage, including on simulators. Device builds require a configured signing team.

Use Xcode-generated string-catalog symbols in the owning UI module. Keep resource and interpolation behavior covered by integration tests.

[Architecture](Architecture.md) describes ownership and dependency rules; [Decisions](Decisions.md) records durable constraints. Module READMEs explain purpose and boundaries. Keep API details in source comments and harness launch options in the owning module README.

## CI skip rules

The Tests workflow always checks CI shell syntax and skip-rule regressions. It classifies the whole main push or the PR's merged diff before starting the simulator job, and records each main push's release decision for TestFlight Publish. The required `test` check still reports failures from these lightweight checks when simulator work is skipped.

| Changes | Simulator tests | TestFlight upload |
| --- | --- | --- |
| Documentation, module READMEs, license, Git ignore rules, Swift formatting rules | Skip | Skip |
| Tests, development harnesses, Tests workflow | Run | Skip |
| Public-beta workflow and other CI helpers | Skip | Skip |
| App/package code, resources, entitlements, manifests, signed-release workflow/helpers, unknown paths | Run | Run |

Missing comparison history runs both jobs. Failed or cancelled Tests runs cannot publish. Public Beta skips release events without a build artifact; hourly/manual retries select the latest successful release with an unexpired artifact, so no-op releases do not hide builds awaiting Apple review.
