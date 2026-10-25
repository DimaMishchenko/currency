# Widget haptics experiment

Related to [#92](https://github.com/DimaMishchenko/currency/issues/92). Keep feedback disabled in normal builds until the physical-device checks below pass. The experiment asks whether an intent can request useful vibration without opening Currency or slowing widget actions. It does not establish a shipping haptic design.

## Findings

Currency supports iOS 26 and later. `WidgetAction` executes in the widget extension and commits the existing widget action before returning. The app's `AppHaptics` driver belongs to active app scenes; using it from a background extension would not preserve that lifecycle.

| Approach | Evidence and decision |
| --- | --- |
| SwiftUI `sensoryFeedback` or UIKit feedback generators | Apple's [haptic guidance](https://developer.apple.com/documentation/applepencil/playing-haptic-feedback-in-your-app) describes foreground execution and system-controlled feedback. These APIs are not evidence of background widget support. |
| View gestures or changing a widget's `@State` | WidgetKit archives and renders the view separately. Run the experiment in the existing intent, where the action actually executes. See [widget interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities). |
| `AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)` inside `perform()` | The [public function](https://developer.apple.com/documentation/audiotoolbox/audioservicesplaysystemsound(_:)) documents vibration on supported devices and no effect on others. A [firsthand August 2024 report](https://www.reddit.com/r/iOSProgramming/comments/1er4lli/) describes success from an interactive widget intent. That historical observation motivates this prototype; it does not verify current iOS behavior. |
| Numeric system sound IDs, notification tricks, or audio/Live Activity intent conformances | Do not use undocumented sound IDs or unrelated capabilities to change execution privileges. Running in the app process alone does not establish foreground haptic eligibility. |

The public vibration constant has no intensity or pattern parameter. It cannot reproduce the app's subtle selection tick or two-beat transition. The function returns no success indication, so a successful intent or build cannot prove that feedback occurred. The AudioToolbox reference also does not establish how this request interacts with every current haptic preference. Measure that on hardware rather than inferring the behavior of UIKit.

## Opt-in prototype

The widget source requires both `DEBUG` and `WIDGET_HAPTICS_EXPERIMENT`. Normal Debug and Release builds leave the experiment off. Keep `DEBUG` out of Release compilation conditions.

After generating the workspace, build a Debug app for an owned simulator or a signed physical iPhone:

```sh
set -o pipefail
xcodebuild build -workspace Currency.xcworkspace -scheme Currency \
  -configuration Debug -destination 'platform=iOS,id=<physical-UDID>' \
  -derivedDataPath <isolated-directory> \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG WIDGET_HAPTICS_EXPERIMENT' \
  2>&1 | xcbeautify
```

Device signing uses the normal project setup. Install that app and add its Calculator widget to the Home Screen. A simulator can verify actions but cannot establish tactile output. To return to the baseline, rebuild without the override and reinstall.

The request follows successful action execution and recognizes the existing command encoding. It adds no sleep, retry, detached task, audio playback, notification, persistence, or foreground launch. Keypad and currency-selection controls use the same path; any preset controls that use `WidgetAction` do too. There is no separate widget swap command. Selecting another active currency provides the relevant conversion-direction interaction. A recognized command may already be at its boundary, such as deleting an empty amount; the prototype measures tap acknowledgement rather than claiming every tap changed a value.

## Physical acceptance

Record the iPhone model, iOS version/build, tested commit and compile conditions. Test the actual Home Screen widget, with Currency backgrounded and then terminated. Compare an experiment build with a normal build on the same device.

- Tap digits, decimal, delete and clear individually, then enter a known amount rapidly. Verify the exact final value and both widget-to-app and app-to-widget sharing. Observe missing, delayed, duplicate or excessive vibration and whether the app unexpectedly opens.
- Change the active currency repeatedly and exercise available presets. Verify conversion values and unchanged widget configuration. Compare the sensation with the app's selection feedback; record whether the vibration is too strong for frequent keys.
- Repeat with System Haptics on/off, each available Sounds & Haptics vibration policy, silent/ring mode, and Accessibility vibration disabled. Record the settings separately. A request must not circumvent a user's disabled-vibration preference.
- Check low-power mode and an unsupported device where available. Actions must remain usable without feedback. Check a mirrored iPhone widget on Mac before broadening the scope: its intent runs on the phone and could produce unexpected remote vibration.
- Confirm the normal build remains silent and the experiment cannot be enabled by the custom flag alone in Release. Record whether any vibration arrives after the visible interaction has finished.

Do not interpret one API call as proof of one physical pulse. The system owns playback; repeated-tap behavior is an acceptance question.

## Recommendation and current limit

Keep this as an opt-in experiment. If hardware confirms reliable, preference-respecting feedback but the pulse is too strong for a keypad, consider a separate proposal limited to infrequent selection actions. If feedback is inconsistent, delayed, or violates preferences, remove the prototype and close the experiment with that evidence. Shipping requires a deliberate decision after those checks.

On 2026-10-25, device discovery listed the physical iPhone as unavailable. No physical model/iOS result or tactile pass is claimed. Issue #92 must remain open until its physical acceptance and shipping recommendation are resolved.
