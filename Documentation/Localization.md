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

## Validation

1. Audit active catalog entries and remove strings whose former UI has been removed.
2. Translate every active entry in all 14 languages, including accessibility text,
   permission messages, widget configuration, intent dialogs and shortcut variants.
3. Declare the supported languages in the app and widget extension manifests.
4. Check coverage, substitution placeholders and multiline copy in CI with
   `python3 Scripts/CI/check_localizations.py`. After a source build, also pass
   `--strings-data <DerivedData>` to detect uncatalogued production strings.
5. Verify generated accessors against compiled module bundles and run the app and
   native intent tests.

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
