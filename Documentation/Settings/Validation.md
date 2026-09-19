# Settings and accent validation — 2026-09-19

## Final implementation

- SettingsFeature depends on CurrencySupport and ExchangeRates. CurrencyApp supplies current converter rates, refresh, location management, and onboarding replay callbacks. Settings does not own a rate service or import ConverterFeature.
- AppAppearance persists System/Light/Dark and named adaptive accents in app-local UserDefaults. CurrencyApp applies these at its scene root. Widgets retain their system appearance.
- Settings has a large title. Theme uses a native menu picker. Accent uses a native menu with colored icons and the platform's left selection checkmark. Only the trailing selected value is the menu label/transition source; its color dot and name have an explicit 8-point gap.
- Settings and home-menu row icons inherit accent; toolbar triggers and controls retain their default tint. The home menu contains Manage currencies and Settings. Refresh remains in Settings → Rates and the converter's pull-to-refresh/accessibility action.
- Sources and acknowledgement titles use primary text color. External-link indicators and license links remain accented. Onboarding replay uses a setup-card symbol without a description.
- Rates use leading-aligned currency/provider/timestamp rows and a short offline/fees footer. Published, Retrieved, and Last trade retain their distinct meanings.
- Feedback is a non-interactive Coming soon placeholder. Version/build values come from Bundle.main.
- Location delegates to the host: not-determined authorization opens the existing setup sheet; previously requested authorization opens the public Settings URL. This action does not itself request permission or location. The setup sheet retains the explicit Use my location action.

## Automated validation

The review run uses `/tmp/currency-settings-build` on simulator `BCEBD877-0415-4D19-83CB-CFEAFE1A2E37`.

- CurrencySupport: 51 tests passed, covering persistence, observation, and the nine-accent contrast matrix in light/dark and standard/increased contrast.
- CurrencyIntegrationTests: 75 tests passed after review fixes. The permission-routing regression exercises not-determined, denied, authorized, restricted, and a return to not-determined without prompting or locating.
- Debug and Release builds passed. Strict Swift formatting on every changed/new Swift file and `git diff --check` passed.
- Independent subagent review covered the entire patch. Its P2 first-time Location dead end was fixed and two unused strings were removed. The second review found no remaining actionable findings.

## Native validation

Isolated iPhone 17 Pro, iOS 26.5, named Currency Settings Review. The verified Debug bundle is `com.dimasike.currency.d`; read the built Info.plist before installing because a separately installed `com.dimasike.currency` can display stale UI. Device Hub supplied native interaction and accessibility inspection; serve-sim input did not work on this Xcode installation.

- After resetting location permission, Settings → Location opened the setup sheet with the explicit Use my location button and no system permission prompt.
- Theme and accent menus opened; selecting Red/Light updated the app immediately. Native accent swatches retained each color and the selected value's accessibility name.
- Sources and Acknowledgements displayed neutral titles, with links and license credits intact.
- Rates and Settings were inspected at normal and largest accessibility text sizes; content wrapped and scrolled.
- Refresh now updated visible timestamps without leaving Rates. Onboarding replay returned to the welcome flow with existing currencies.
- The feedback placeholder and actual Version 1.0 · Build 1 footer were visible after scrolling.
- Chart tapping reproduced a missed point inside the former padded frame. An explicit rectangular content shape over the 44 × 70-point label fixed that point, a lower-corner point, and tapping while the keypad was open. Neighboring amount taps still opened the keypad.


Physical-device routing to the app-specific system Settings page remains unverified. On this simulator, the public URL can open the Settings home page; no private Settings URL is used. Native validation covers iOS 26.5 and representative accents, not every OS/device combination.
