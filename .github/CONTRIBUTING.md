# Contributing to Currency

Thanks for helping improve Currency. Follow the [code of conduct](CODE_OF_CONDUCT.md) in issues, pull requests and other project spaces.

## Get started

Install Xcode 27.1 (the current CI toolchain) and [mise](https://mise.jdx.dev/), then run:

```sh
mise install
mise exec -- tuist install
mise exec -- tuist generate
```

Open the `Currency` scheme and choose an iOS 26+ simulator. No Tuist account is required. See [Development](../Documentation/Development.md) for toolchain pins, schemes, commands and CI behavior, and [Architecture](../Documentation/Architecture.md) for module ownership and dependencies.

## Issues and questions

Search [existing issues](https://github.com/DimaMishchenko/currency/issues) before opening one through the issue template. For bugs, include reproduction steps, expected and actual behavior, app build, device and OS version, and relevant screenshots or redacted logs. For features, describe the problem and desired outcome. Discuss substantial changes in an issue before starting implementation.

Issues are public. Remove personal information and secrets. Use [Support](SUPPORT.md) for questions or private help and [Security](SECURITY.md) for suspected vulnerabilities.

## Pull requests

Create a focused branch from `main` and use the [pull request template](pull_request_template.md). Link the related issue, explain the change and list verification results and remaining gaps. Keep unrelated edits out of the PR. Use a concise Gitmoji title such as `📝 docs: clarify setup`.

Before requesting review:

- Follow the existing Swift style and run `bash Scripts/CI/check_swift_format.sh` and `git diff --check`.
- Run relevant tests for the affected behavior using the schemes and commands in [Development](../Documentation/Development.md). Add or update outcome checks when functionality changes.
- For UI changes, validate the affected states and interactions in the running app and include screenshots or a short recording. Use the [feature map](../Documentation/FeatureMap.md) and [E2E guide](../Apps/Currency/Tests/E2E/README.md) to select journeys and document coverage gaps. Update these documents when functionality or coverage changes.
- Use an owned simulator targeted by UDID and a separate derived-data directory when working in parallel. Pipe command-line `xcodebuild` output through `xcbeautify` with `set -o pipefail`.

Documentation-only changes need link and content checks; native builds are unnecessary unless executable code, resources or behavior also change. Report checks you could not run. Maintainers may request revisions before merging.

Source contributions are covered by the repository's [MIT license](../LICENSE). Preserve separate [data](../Documentation/DataSources.md) and [asset](../Documentation/ThirdPartyAssets.md) license notices.
