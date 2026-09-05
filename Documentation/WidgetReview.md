# Widget-focused revision

Converter: small focuses on one pair; medium shows three destinations; large shows up to eight. Lists of one to three stay in one column, longer lists use two columns. Large keys expand for lists of up to six, then compact for seven or eight. Overflow is disclosed with a +N count. Amounts, emoji flags and publication dates remain visible.

Currency board: medium shows six, large twelve, with no keypad. Uses the same shared selection and order. Quick rate: inline and rectangular Lock Screen families display the first destination. A circular widget would force excessive truncation, so it is omitted. Daily feeds do not justify a continuously updating Live Activity. Travel denomination tables and independent per-widget lists are useful future options, not implemented in this revision.

The app exposes widget discovery directly in its header. The amount dock uses GlassEffectContainer, matching glassEffectID and matchedGeometry glass transitions. Its expanded shape uses iOS 26 ConcentricRectangle with uniform concentric corners and a minimum radius for rectangular windows. Reduce Motion disables the explicit spring. No private screen-radius APIs are used.

References: [Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [ConcentricRectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle).

Validation: signed iOS Simulator build and all ten RateCore tests pass. The app keypad, widget guide and small/six-currency large Home Screen widgets were visually inspected. Board and Lock Screen families compile; real-device interaction latency and frame pacing still need profiling. WidgetKit controls updates; no 60 fps claim is made.
