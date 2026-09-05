# Currency / the quiet ledger

The screen is a personal currency list. One source amount leads; every row answers the same question in another currency. Warm paper in light mode, near-black olive in dark mode. Color comes primarily from flag emoji. Crypto uses a coin rather than a misleading country flag.

## Composition

A small wordmark and options control, a generous source amount, then a flat list. Values align on the trailing edge; codes and names anchor the leading edge. Fine separators establish rhythm without cards. Secondary information stays in a sheet, where each publication date and provider remains inspectable.

The default list contains six destinations. The keyboard is tucked into one floating control so the list gets most of the screen. Entering an amount expands a single glass keypad; tapping Done returns to the ledger. Native sheets support search, removal, and reordering.

## Signature interaction

Tap a destination to promote it to the source. The converted amount becomes the editable amount, and the previous source takes the destination’s place. Currency identity moves with a short spring; values use numeric transitions. No looping glow, parallax, or ambient animation. Reduce Motion disables custom movement; keypad feedback uses the system selection haptic.

## HIG decisions

[Apple’s material guidance](https://sosumi.ai/design/human-interface-guidelines/materials) places Liquid Glass on controls and navigation, with restrained use. Accordingly, the currency rows are plain content; glass is reserved for the floating input control, expanded keypad, and options button. Native sheets and menus retain system behavior.

Touch targets in the app are at least 44 points. Currency flags are decorative for VoiceOver; rows announce the currency name, value, and action. Typography responds to Dynamic Type, long numbers scale, and the screen scrolls as needed. Source selection and context-menu actions provide alternatives to the animated row interaction.

## Verification boundaries

The app and widget extension compile with Swift 6. Tests cover migration of previously saved input, ordered destinations, list normalization, and preservation of converted value when promoting a currency. Simulator checks cover light/dark layouts, numeric input, promotion, and list management. Frame rate is not profiled on physical hardware; no 60fps claim is made. Widget input remains subject to iOS scheduling.
