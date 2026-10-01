# Localization

Currency supports English, Simplified Chinese, Japanese, Spanish, German, French,
Brazilian Portuguese, Korean, Traditional Chinese, Italian, Turkish, Russian and Ukrainian.

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
2. Translate every active entry in all 13 languages, including accessibility text,
   permission messages, widget configuration, intent dialogs and shortcut variants.
3. Declare the supported languages in the app and widget extension manifests.
4. Check coverage, substitution placeholders and multiline copy in CI with
   `python3 Scripts/CI/check_localizations.py`. After a source build, also pass
   `--strings-data <DerivedData>` to detect uncatalogued production strings.
5. Verify generated accessors against compiled module bundles, run the app tests and
   native intent tests, and inspect the production app in every language.
6. Exercise Language → system Settings → preferred language → return to Currency;
   inspect longer text at accessibility sizes and representative widget/onboarding screens.

The `NativeLocalizationTests` scheme runs production app screenshots in every language,
Ukrainian widget/tutorial and accessibility text checks, and verifies that Language opens
system Settings. Preferred-language selection is a separate system acceptance check.

Local simulator acceptance verified the language picker and a German relaunch after
selecting Deutsch. Cold app-settings navigation remained on the Settings root on both
iOS 26.5 and iOS 27 simulators despite receiving the correct app destination. Confirm
cold navigation on a physical device before release; the app uses Apple's public URL.

App Store listing copy is managed separately in App Store Connect. Shipping translated
app resources does not publish translated listing text or screenshots.
