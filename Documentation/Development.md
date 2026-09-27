# Development

## Working locally

Use Xcode and the Tuist version pinned in `.mise.toml`. With [mise](https://mise.jdx.dev/), run `mise install` and use `mise exec --` before Tuist commands, or activate mise in your shell. Toolchain and deployment requirements live in the manifests.

Run `tuist install` after changing package dependencies, then `tuist generate` to open `Currency.xcworkspace`. Regenerate after changing manifests or package sources so Tuist can update dependency cache hashes. Changes inside existing app buildable folders do not require regeneration.

- `Currency` builds the app and widget extension.
- `CurrencyTests` builds the shipping app and extension and runs the combined test suite, including rate-core tests.
- `CurrencyHarnesses` builds the isolated development apps. Module READMEs list their harness launch arguments.
- `NativeIntentTests` is a UI-test target for iOS 27 AppIntentsTesting against the installed Currency executable. It completes onboarding in setup and exercises extracted metadata and cross-process execution. Domain and adapter tests stay in existing unit targets; this adds no production module.

For command-line Xcode builds, use `set -o pipefail` and pipe combined output through `xcbeautify`. Use a separate simulator and derived-data directory for parallel work.

## Dependency cache

Tuist integrates local Swift packages through `Tuist/Package.swift` and automatically substitutes available cached dependencies during generation. Normal development does not require authentication or custom build scripts.

Without authentication, Tuist reuses locally cached binaries; downloading shared binaries requires login. `tuist cache` creates binaries; ordinary Xcode builds only consume them.

To warm dependencies on your machine without uploading:

```sh
mise exec -- tuist cache --cache-profile only-external --configuration Debug --no-upload
mise exec -- tuist generate --no-open
```

To upload newly built binaries, authenticate before warming and omit `--no-upload`; binaries already warmed locally are not uploaded again. Main and same-repository PR checks authenticate with GitHub OIDC and warm the shared cache; fork PRs receive no Tuist writer credentials. Warming is optional and CI continues if it fails. See [Tuist's module cache guide](https://tuist.dev/en/docs/guides/features/cache/module-cache).

Use `tuist generate --no-open --cache-profile none` to keep dependencies as source. Signed release archives always use this mode.

Before delivery, run the relevant tests, check affected UI, and verify formatting with `swift format lint --recursive --strict App Domain Features DesignSystem Infrastructure` and `git diff --check`. Outstanding device and release checks live in [GitHub Issues](https://github.com/DimaMishchenko/currency/issues?q=is%3Aissue+is%3Aopen+label%3Averification).

Run native intent tests with `xcodebuild test -workspace Currency.xcworkspace -scheme NativeIntentTests -destination 'platform=iOS Simulator,id=<owned-UDID>' -derivedDataPath <isolated-directory>`, using the output formatting above. CI runs this scheme separately from the unit suite. AppIntentsTesting verifies structured outputs, decimal coercion, chaining, full-catalog queries, indexed code searches, cold/warm detail opening, and visible entity annotations. Annotation tests verify what the app exposes; physical Siri conversations and onscreen interpretation still need device acceptance. Spotlight presentation and ranking remain system controlled.

## Conventions

Keep signing enabled when validating shared App Group storage, including on simulators. Device builds require a configured signing team.

Use Xcode-generated string-catalog symbols in the owning UI module. Keep resource and interpolation behavior covered by integration tests.

[Architecture](Architecture.md) describes ownership and dependency rules; [Decisions](Decisions.md) records durable constraints. Module READMEs explain purpose and boundaries. Keep API details in source comments and harness launch options in the owning module README.

## CI skip rules

The Tests workflow always checks CI shell syntax and skip-rule regressions. It classifies the whole main push or the PR's merged diff before starting the simulator job, and records each main push's release decision for TestFlight Publish. The required `test` check still reports failures from these lightweight checks when simulator work is skipped.

| Changes | Simulator tests | TestFlight upload |
| --- | --- | --- |
| Documentation, module READMEs, license, Git ignore rules | Skip | Skip |
| Tests, development harnesses, Tests workflow, Swift formatting rules | Run | Skip |
| Public-beta workflow and other CI helpers | Skip | Skip |
| App/package code, resources, entitlements, manifests, signed-release workflow/helpers, unknown paths | Run | Run |

Missing comparison history runs both jobs. Failed or cancelled Tests runs cannot publish. Public Beta skips release events without a build artifact; hourly/manual retries select the latest successful release with an unexpired artifact, so no-op releases do not hide builds awaiting Apple review.
