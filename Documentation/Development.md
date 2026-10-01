# Development

## Working locally

Use Xcode and the Tuist version pinned in `.mise.toml`. With [mise](https://mise.jdx.dev/), run `mise install` and use `mise exec --` before Tuist commands, or activate mise in your shell. Toolchain and deployment requirements live in the manifests.

Run `tuist install` after changing package dependencies, then `tuist generate` to open `Currency.xcworkspace`. Regenerate after changing manifests or package sources so Tuist can update dependency cache hashes. Changes inside existing app buildable folders do not require regeneration.

- `Currency` builds the app and widget extension.
- `CurrencyTests` builds the shipping app and extension and runs the combined test suite, including rate-core tests.
- `CurrencyHarnesses` builds the isolated development apps. Module READMEs list their harness launch arguments.
- `NativeIntentTests` is a UI-test target for iOS 27 AppIntentsTesting against the installed Currency executable. It launches the app and completes onboarding once per test process, then waits for extracted metadata before exercising cross-process execution. Data-only cases reuse that bootstrap, except English name/query assertions explicitly relaunch with English arguments because cold intent execution can restart the app in the system language. The annotation case launches a clean UI, and cold conversion/detail cases explicitly terminate the app before invoking intents. Domain and adapter tests stay in existing unit targets; this adds no production module.

`CurrencyTests` lets Swift Testing run independent cases concurrently within each target.
The onboarding suite keeps its transient-state checks serialized. CI reinstalls the app,
launches it through `simctl`, then terminates it before the native suite. This completes fresh-install activation outside XCTest’s background-assertion
handshake. The native suite starts from a stopped app and runs serially on the owned simulator. Each individually selected case performs the same onboarding and metadata bootstrap.

For command-line Xcode builds, use `set -o pipefail` and pipe combined output through `xcbeautify`. Use a separate simulator and derived-data directory for parallel work.

## Dependency cache

Tuist integrates local Swift packages through `Tuist/Package.swift` and automatically substitutes available cached dependencies during generation. Normal development does not require authentication or custom build scripts.

Without authentication, Tuist reuses locally cached binaries; downloading shared binaries requires login. `tuist cache` creates binaries; ordinary Xcode builds only consume them.

To warm dependencies on your machine without uploading:

```sh
mise exec -- tuist cache --cache-profile only-external --configuration Debug --no-upload
mise exec -- tuist generate --no-open
```

To upload newly built binaries, authenticate before warming and omit `--no-upload`; binaries already warmed locally are not uploaded again. Main and same-repository PR checks authenticate with GitHub OIDC and warm the shared cache, except Dependabot PRs. Fork and Dependabot PRs receive no Tuist writer credentials. Warming is optional and CI continues if it fails. See [Tuist's module cache guide](https://tuist.dev/en/docs/guides/features/cache/module-cache).

Use `tuist generate --no-open --cache-profile none` to keep dependencies as source. Signed release archives always use this mode.

Before delivery, run the relevant tests, check affected UI, and verify formatting with `swift format lint --recursive --strict App Domain Features DesignSystem Infrastructure` and `git diff --check`. Outstanding device and release checks live in [GitHub Issues](https://github.com/DimaMishchenko/currency/issues?q=is%3Aissue+is%3Aopen+label%3Averification).

Run native intent tests with `xcodebuild test -workspace Currency.xcworkspace -scheme NativeIntentTests -destination 'platform=iOS Simulator,id=<owned-UDID>' -derivedDataPath <isolated-directory>`, using the output formatting above. CI runs this scheme separately from the unit suite. AppIntentsTesting verifies structured outputs, decimal coercion, chaining, full-catalog queries, indexed code searches, cold/warm detail opening, and visible entity annotations. Annotation tests verify what the app exposes; physical Siri conversations and onscreen interpretation still need device acceptance. Spotlight presentation and ranking remain system controlled.

## Dependency updates

[Dependabot](../.github/dependabot.yml) checks GitHub Actions in all `.github/workflows` files weekly, including Tests, TestFlight Publish, and Public Beta. Minor and patch updates share one group; major updates get separate PRs. At most five version-update PRs can be open at once.

Update PRs run the existing Tests workflow and its required `test` check. Changes to Tests or TestFlight Publish run simulator tests; Public Beta changes run the lightweight CI checks. Dependabot PRs skip authenticated Tuist cache warming and can build from source without Actions secrets. Signing and release secrets stay in the main-only release workflows.

Swift packages currently use only local path dependencies. Add a `swift` ecosystem entry for each manifest directory that introduces an external Swift package, including `/Tuist` if `Tuist/Package.swift` owns it. Dependabot does not cover the Tuist pin in `.mise.toml` or tools installed by Homebrew or download scripts; review those separately.

After landing a configuration change, check the first [Dependabot update job](https://github.com/DimaMishchenko/currency/actions/workflows/dependabot/dependabot-updates) for successful discovery and review the CI results on its update PRs. Use Insights → Dependency graph → Dependabot → Check for updates to request another check.

## Conventions

Keep signing enabled when validating shared App Group storage, including on simulators. Device builds require a configured signing team.

Use Xcode-generated string-catalog symbols in the owning UI module. Keep resource and interpolation behavior covered by integration tests. Run `python3 Scripts/CI/check_localizations.py` for language coverage, placeholder and line-break validation; see [Localization](Localization.md) for supported languages and the system preference flow.

[Architecture](Architecture.md) describes ownership and dependency rules; [Decisions](Decisions.md) records durable constraints. Module READMEs explain purpose and boundaries. Keep API details in source comments and harness launch options in the owning module README.

## CI skip rules

The Tests workflow always checks CI shell syntax and skip-rule regressions. It classifies the whole main push or the PR's merged diff before starting the simulator job, and records each main push's release decision for TestFlight Publish. The required `test` check still reports failures from these lightweight checks when simulator work is skipped.

| Changes | Simulator tests | TestFlight upload |
| --- | --- | --- |
| Documentation, module READMEs, license, Git ignore rules | Skip | Skip |
| Tests, development harnesses, Tests workflow, Swift formatting rules | Run | Skip |
| TestFlight notes generator | Skip | Run |
| Public-beta workflow and other CI helpers | Skip | Skip |
| App/package code, resources, entitlements, manifests, signed-release workflow/helpers, unknown paths | Run | Run |

Missing comparison history runs both jobs. Failed or cancelled Tests runs cannot publish. Public Beta skips release events without a build artifact; hourly/manual retries select the latest successful release with an unexpired artifact, so no-op releases do not hide builds awaiting Apple review.

## TestFlight testing notes

TestFlight Publish generates notes from the exact tested commit before uploading. Notes list app changes since the previous published build, with commit subjects, short hashes, and checks for the affected features. Commits that only change documentation, tests, CI, or dependency manifests are omitted. When the previous build has no recorded commit or usable history, notes explicitly describe a bounded selection of recent changes. A build with no app changes receives a short maintenance fallback.

The `currency-release-build` artifact stores `CurrencyBuildId.txt`, `CurrencyCommit.txt`, and `CurrencyTestNotes.txt`. Publication writes the notes directly to the build's English TestFlight localization. Public Beta reuses the saved notes during promotion and retries, so later main-branch changes cannot alter an older build's description.

Notes follow the [ASC text restrictions](https://github.com/rorkai/App-Store-Connect-CLI/blob/5.7.0/internal/cli/shared/test_notes.go), removing rejected characters including Gitmoji and variation selectors. The same sanitization applies when reading older artifacts. A notes-generator change triggers publication after the automation checks, so notes fixes reach TestFlight without requiring an app-code change.

Run `python3 Scripts/CI/test_testflight_notes.py` alongside `python3 Scripts/CI/test_skip_rules.py` when changing this automation.
