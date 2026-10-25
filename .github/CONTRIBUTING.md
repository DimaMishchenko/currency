# Contributing

Follow the [code of conduct](CODE_OF_CONDUCT.md). Search [existing issues](https://github.com/DimaMishchenko/currency/issues) before reporting a bug or proposing a feature. Include reproduction steps, expected behavior, app build and device/OS version. Discuss substantial changes before implementing them. Report vulnerabilities privately through [Security](SECURITY.md).

## Setup

Install Xcode 27.1 and [mise](https://mise.jdx.dev/), then run:

```sh
mise install
mise exec -- tuist install
mise exec -- tuist generate
```

Open the `Currency` scheme. See [Development](../Documentation/Development.md) for build and test commands.

## Pull requests

Keep changes focused, use the [PR template](pull_request_template.md), link the issue and describe validation. Run relevant tests, `bash Scripts/CI/check_swift_format.sh` and `git diff --check`. For UI changes, include screenshots or a recording; use the [E2E guide](../Apps/Currency/Tests/E2E/README.md) to select journeys and update coverage when behavior changes.

Contributions use the repository’s [MIT license](../LICENSE). Keep personal information and secrets out of public issues and PRs. See [Support](SUPPORT.md) for help.
