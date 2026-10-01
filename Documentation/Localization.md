# Localization

Currency supports English, Simplified Chinese, Japanese, Spanish, German, French,
Brazilian Portuguese, Korean, Traditional Chinese, Italian, Turkish, Russian, Ukrainian and Estonian.

## Ownership and behavior

Each UI module owns its string catalog. The app owns App Intents, shortcut phrases and
permission text; the widget extension owns configuration metadata. Currency names,
number formatting and dates use Foundation locale APIs. Currency identifiers, provider
names and the Currency brand remain stable across languages.

Settings → Language opens Currency’s page in system Settings using
`UIApplication.openSettingsURLString`. iOS owns the preferred app language. Currency
has no separate language preference or runtime locale override. The app declares
`UIPrefersShowingLanguageSettings` so the system language picker is available even
when the device has only one preferred language. Region formatting and
saved currencies retain their existing behavior.

## Implementation and acceptance

1. Audit active catalog entries and remove strings whose former UI has been removed.
2. Translate every active entry in all 14 languages, including accessibility text,
   permission messages, widget configuration, intent dialogs and shortcut variants.
3. Declare the supported languages in the app and widget extension manifests.
4. Check coverage, substitution placeholders and multiline copy in CI with
   `python3 Scripts/CI/check_localizations.py`. After a source build, also pass
   `--strings-data <DerivedData>` to detect uncatalogued production strings.
5. Verify generated accessors against compiled module bundles, run the app tests and
   native intent tests, and inspect the production app in every language.
6. Exercise Language → system Settings → preferred language → return to Currency;
   inspect longer text at accessibility sizes and representative widget/onboarding screens.

The `NativeLocalizationTests` scheme captures Home, Settings, currency categories and
history in every language, exercises crypto-category and year-to-date selection, checks
Ukrainian and Estonian widget/tutorial and accessibility text sizes, and verifies that Language opens
system Settings. This is an explicit visual acceptance suite, excluded from routine CI.
Repeated app launches, screen navigation and screenshot capture across all languages
take several minutes.
Run it when adding a language, changing layouts or reviewing a release, with a task-owned
simulator targeted by UDID:

```sh
set -o pipefail
xcodebuild test \
  -workspace Currency.xcworkspace \
  -scheme NativeLocalizationTests \
  -destination "platform=iOS Simulator,id=$CURRENCY_TEST_SIMULATOR" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  CODE_SIGN_IDENTITY=- 2>&1 | xcbeautify
```

Use `-only-testing:NativeLocalizationTests/NativeLocalizationTests/testEstonian`, for
example, to review one language. Preferred-language selection is a separate system
acceptance check.

Routine CI checks every catalog's language coverage, completed translations, placeholders
and line breaks, then audits compiler-extracted strings against their owning catalogs.
The existing `CurrencyTests` run also resolves compiled module resources and substitutions
for every supported language. These checks reuse the normal build and test process; they
add no app launches or screenshot collection. Each dedicated catalog check has a 25-second process timeout,
for a combined 50-second budget with headroom below one minute. A stalled or failed check
fails CI. The measured combined duration before this change was one second.

Preferred-language selection and German relaunch were verified in system Settings on
simulator. Language navigation and switching were also confirmed on a physical device.
Cold app-settings navigation on some simulators remains a system limitation.

Currency names use sentence capitalization while preserving the rest of each localized
name. Compact control labels have separate full accessibility descriptions. Segmented
pickers use a native menu when the widest label cannot fit in every segment, and at
accessibility text sizes. This applies to currency categories, history ranges and widget
size/configuration choices.

App Store listing copy is managed separately in App Store Connect. Shipping translated
app resources does not publish translated listing text or screenshots.
