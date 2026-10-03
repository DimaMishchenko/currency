# Adaptive layouts

Home uses scene-local geometry to choose a stacked converter, two columns, or tabletop placement. On iOS 27.1, active physical divisions come from `GeometryProxy.reservedRegions`. Controls and results stay clear of the returned frame; tabletop places results above the fold and input below it. Unfolded windows use their available width, aspect ratio, and Dynamic Type size instead of device names. Tall portrait windows keep the source and results stacked on a shared leading edge. Older systems retain geometry-based adaptation.

The converter retains its model and source/list identities across layout changes. Wide layouts expose the keypad without starting an editing session until input occurs. Constrained source and keypad regions scroll independently. The collapsed input dock and expanded keypad share one native glass identity and matched-geometry transition. Expanded keypads retain concentric corners, safe-area-aware controls, and a bounded key grid. Source typography only contracts when the available region is genuinely short; editing alone does not shrink it.

Onboarding and widget tutorials share `AdaptivePairLayout` for preview/explanation placement, retaining the current onboarding state and History widget content. Details separates the chart and controls around physical divisions, including a compact chart summary above the laptop fold. Currency selection and location onboarding constrain content width. Onboarding uses compact currency summaries and a vertically scrolling recommendation grid, with a measured compact footer. Unfolded portrait windows stack content; landscape and physical divisions use paired regions. Widget pages use native full-page snapping. Compact currency selection uses segments and native toolbar search. The app manifest declares all iPad orientations.

Apple's [adaptation guidance](https://developer.apple.com/videos/play/tech-talks/111463/) informs division handling, persistent state, and native presentation behavior.

## Verification

The October 2 refresh was rebuilt over main `8a8115d`, preserving the previous adaptation separately. The final Xcode 27.1 beta production build and 132 affected tests passed across DesignSystem, Conversion, Home, Onboarding, CurrencyDetails, and WidgetOnboarding. Strict formatting, localization validation (672 entries across 15 catalogs), and independent code review passed. The initial critical review missed recommendation clipping subsequently reported by the user; the onboarding follow-up below supersedes its visual sign-off.

Native validation covered:

- Duo closed portrait and both landscape directions: readable source amount, bottom-attached keypad, segmented picker, onboarding, and tutorial clipping fixes.
- Duo open landscape: keypad bottom material, stable onboarding transitions, readable tutorial widget, and one-page carousel gestures through History and Currency Board.
- Book and laptop: onboarding placement around the fold, preserved selection state, and laptop Details chart/axes above the fold with controls below.
- iPad portrait: aligned source/results, unchanged source typography when editing, and bounded keypad controls. The earlier refresh also checked iPad onboarding completion, rotation while editing, and dark landscape at the largest Dynamic Type size.

Evidence is retained under `.validation/polish-20261002/` and `.validation/revisit-20261002/`. In the polish folder, `home-closed-landscape-a-final.png`, `home-closed-landscape-b-final.png`, `home-open-material-verified.png`, `ipad-keypad-verified.png`, `picker-compact-final.png`, `details-laptop-final.png`, and `transition-frames-final.png` represent the final checks. Earlier captures remain as before/iteration evidence.

Remaining coverage limits: narrow iPad window resizing and exhaustive combinations of every sheet, pose, and accessibility size were not rechecked. Tent pose was entered, but Device Hub presented the device edge-on, so that pose has no accepted visual capture. Geometry tests do not replace these native checks.

### Glass keyboard follow-up

The expanded keyboard retains native Liquid Glass and morphs from/to the collapsed amount dock using the same glass identity. The temporary regular-material treatment was removed after design feedback. Bottom corners use a 24-point minimum when no enclosing rounded edge is resolved. `build-glass-final.log` records the successful follow-up build; `glass-morph-restored.mp4`, `glass-open-frames.png`, and `glass-close-frames.png` show the native opening/closing transition before the corner fallback. Earlier material screenshots are superseded for keyboard styling.

The safe-area follow-up extends the expanded glass surface into the bottom container inset while padding only the key grid. Each bottom corner resolves independently against its enclosing geometry, retaining a rounded minimum for interior pane corners. The collapsed dock and shared morph identity are unchanged. `build-glass-safe-area.log` passed; `glass-safe-area-stacked.png` shows portrait coverage and `glass-safe-area-portrait.png` (landscape capture despite its name) shows the column layout. Native checks confirmed keys remain above the safe area.

### Onboarding layout review follow-up

The recommendation rail was replaced by intrinsic-height rows: one column in narrow regions, two columns where they fit, capped at 640 points. Base and destination steps share compact summary heights. Compact footers measure their content instead of reserving a fixed fraction of the screen or an unused Later action. The stage is top-aligned during transitions and resets its scroll position when changing steps. Landscape and physical-fold layouts retain independently scrollable content and controls.

The welcome card can shrink within a narrow pane; the finale orbit follows the actual available height; widget cards fit the carousel budget. On tall windows, a 380-point carousel-stage cap keeps the widget preview and controls together. The glass keyboard and its shared morph identity are unchanged by this follow-up.

Evidence is in `.validation/onboarding-review-20261002/`: six-step matrices for closed portrait (`closed-portrait-final`), both closed landscape orientations, open landscape (`open-current`), open portrait, iPad portrait, laptop, and Book. The initial `ipad-current` matrix and blank launch captures are intermediate evidence, not accepted results; `ipad-portrait-final` and `ipad-widget-centered.png` supersede them. Native interaction verified scrolling the base list to CHF, selecting it, continuing, returning, and preserving CHF while resetting the list to the top.

The production build passed and all 64 relevant tests passed (DesignSystem 17, Onboarding 36, WidgetOnboarding 11). Independent code review found no remaining P1/P2 issue. The critical designer reviewed settled matrices, required the additional iPad widget-stage correction, and accepted the final compact, Book, and laptop compositions with no new P1/P2 findings. The latest production build was installed on both task-owned simulators without resetting app data. Exhaustive Dynamic Type/localization combinations and narrow iPad window resizing remain outside this follow-up's native coverage.

The follow-up replaced alignment-based carousel scrolling with native `.paging` after a gesture appeared to skip the middle preview. This supersedes the earlier paging acceptance: the final modifier builds and renders correctly, but a reliable final swipe-through has not been confirmed. Device Hub gestures were inconsistent and the device-targeted helper reported a zero-size display. Page snapping remains an explicit native interaction verification gap.

### Closed transition and completion follow-up

The closed selection-to-Home-Screen transition now measures only the incoming step while retaining step-keyed outgoing views throughout the fade. Localized footer text reserves a consistent footprint across standard text sizes, preventing a second position change when outgoing text disappears. Accessibility sizes retain content-driven sizing and scrolling.

The validation harness previously ignored `.completed`, leaving an already-completed model on the finale; its intentionally disabled post-completion Back action made the screen appear frozen. The harness now presents an explicitly labeled completion destination and a verified Restart validation action. Production completion routing was already wired correctly and was verified through Settings replay: final Back returns to widgets, Later returns to the finale, and Get started reveals the converter with EUR 78,123 and its currencies preserved.

Both final builds and strict formatting/diff checks passed. Independent review cleared the state-preserving layout. Native closed-Duo recordings and frames are in `.validation/onboarding-transition-20261002/`; `final-transition.mp4` covers the final selection/Home Screen/widgets transition implementation, while `production-flow.mp4` and `production-completed.png` prove production Back and completion. The task ends with the production app open, rather than the harness.

### October 3 refinement

The keypad keeps its native glass, concentric corners, safe-area coverage, and shared morph identity. Transparent horizontal scroll gutters let its shadow extend past the input column without a hard seam. Persistent keypads retain Add currency while editing; Done remains only where it dismisses the keypad.

Details now puts the large history graph in the upper laptop region and the summary, range, and source below. Closed landscape uses a compact summary and a minimum 220-point plot, with scrolling to reach the range and source rather than compressing the graph.

Onboarding scenes now own independent, step-keyed scroll views. Departing scenes retain their last viewport height and scroll position until the fade completes; accessibility footers retain their own step during departure. A hidden native search item preserves toolbar geometry. This supersedes the earlier shared-scroll/custom-layout approach. The finale drops the redundant subtitle and centers its action in split layouts. Recommendation columns stay balanced, with a shorter full-width More currencies row when it falls outside the grid.

Production and harness builds passed. All 94 affected tests passed, followed by a final 36-test Onboarding rerun after the transition refinement. Strict formatting and diff checks passed, and independent code and critical visual reviews cleared the final changes. Native evidence in `.validation/polish-20261003/` includes `closed-landscape-keyboard.png`, `laptop-keyboard.png`, `details-laptop.png`, `details-closed-landscape-final.png`, `details-closed-landscape-scrolled.png`, `base-grid-final.png`, the two `finale-*.png` captures, `selection-home-independent-scrolls.mp4`, and `closed-portrait-final-flow.mp4`. Earlier transition recordings and the non-final landscape Details capture are rejected iterations. Final Get started was verified in the validation harness; production completion was verified in the preceding follow-up. Existing exhaustive accessibility/window-resizing and widget paging coverage limits remain.

### October 3 onboarding geometry follow-up

Geometry-driven Home Screen, widget showcase, and finale scenes now receive an explicit viewport height inside their step-owned scroll view. This fixes the collapsed laptop previews while retaining cached outgoing bounds. The widget showcase measures its full controls block, fits the preview into the remaining height, and reserves caption clearance; larger content remains scrollable.

Back and Search share an upper-leading glass toolbar item with 44-point targets. Back keeps that placement when Search disappears, replacing the earlier hidden trailing Search item. Native leading/primary placements alone left Search detached from Duo's Back control, so the controls are grouped explicitly.

Production and harness builds, strict formatting, and all 36 Onboarding tests passed. Native evidence is in `.validation/onboarding-geometry-20261003/`: laptop Home Screen/widgets/finale were exercised; Get started reached the harness completion destination; closed caption, Back navigation, Search presentation, and grouped controls across closed/open/laptop poses were verified. The final caption capture is `closed-widgets-verified.png`; the earlier `closed-widgets.png` is rejected. Independent code review cleared the sizing change and the critical designer accepted the corrected caption and toolbar. Recommendation lists remain scrollable and may show partial rows at their viewport boundary. Exhaustive accessibility/localization and additional iPad window sizes were not rerun in this focused follow-up.
