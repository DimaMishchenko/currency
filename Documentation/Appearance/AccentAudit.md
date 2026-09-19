# Accent usage audit

Validated 19 September 2026 on the isolated iPhone 17 Pro simulator, iOS 26.5.

The app root owns tint. Features inherit it for actions, selections, and chart emphasis. General content stays neutral. The default accent remains the adaptive system label color.

| Surface | Treatment |
| --- | --- |
| Toolbars | System default tint for navigation, Close, Back, Search, menu triggers, and keyboard toolbar actions; reset inherited app tint with `.tint(nil)` |
| Primary onboarding, widget-guide, tutorial, and location actions | Native prominent buttons with the selected accent fill and a contrasting black or white label |
| Currency picker and onboarding choices | Neutral currency codes/names; selected checkmarks and onboarding borders use accent |
| Converter | Neutral amounts, source currency, keypad digits, widget shortcut, overflow trigger, and Add currency (+); Done uses accent |
| Home overflow menu | Accent action icons with neutral labels; the toolbar trigger retains system default tint |
| Settings | Accent row icons with neutral navigation labels and color names; selection checks and action links inherit tint; theme and accent choices use native menu pickers |
| Rate history | Accent line and selected point; neutral values, axes, grid, and reference information |
| Tutorial and widget gallery | Accent active progress/page indicators; neutral inactive indicators |
| Widget previews and simulated system interfaces | Retain their own system styling; the app accent does not recolor widget content, sample app icons, flags, metals, or illustrative backgrounds |

`AppAccentLabel` resolves its label color against the same adaptive UIKit system color used by `AppAppearance.Accent.color`. SwiftUI color scheme and increased-contrast settings are explicitly passed to the foreground resolver. Disabled labels use secondary system text. Native button geometry, interaction, and disabled fill remain platform-owned.

## Validation

- Debug app build passed.
- CurrencySupport: 51 tests passed, including all nine accents in light/dark and normal/increased contrast. The test checks the public foreground API used by the UI and requires at least 4.5:1 against the solid accent color. This checks button-label contrast, not an app-wide accessibility certification.
- CurrencyIntegrationTests: 74 tests passed.
- Swift formatting and `git diff --check` passed.
- Orange/light walkthrough: welcome CTA, base and destination selections, widget onboarding, converter keypad, Add currency picker, and the location permission-recovery action. Currency labels and digits stayed neutral; primary labels rendered black on orange.
- Live Settings changes to dark/purple updated checkmarks, then the converter's history chart and widget tutorial inherited the new tint. Prominent button labels remained readable, and widget previews retained their own styling.
- Visual checks cover the iOS 26.5 simulator and representative accents. Automated contrast checks cover the full palette; physical-device rendering and every OS version were not rechecked for this audit.

The workspace's current Debug bundle is `com.dimasike.currency.d`. Verify `CFBundleIdentifier` in the built app when installing a new build; a separately installed `com.dimasike.currency` can show stale UI.

Toolbar follow-up: reset toolbar content to system default tint and removed explicit foreground overrides from the converter toolbar icons. Verified a neutral Close control beside the purple chart on iOS 26.5.
