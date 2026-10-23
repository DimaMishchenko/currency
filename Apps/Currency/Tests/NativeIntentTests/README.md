# Native UI tests

`NativeIntentTests` verifies system App Intent integration.
`AccessibilityVoiceOverTests` uses the iOS 27 XCTest VoiceOver service to check
spoken converter values and forward/backward focus traversal. It restores the
original VoiceOver state and attaches actual speech and screenshots to xcresult.

Run on an explicitly owned iOS 27 or later simulator:

```sh
set -o pipefail
xcodebuild test -workspace Currency.xcworkspace -scheme NativeIntentTests \
  -destination "platform=iOS Simulator,id=$CURRENCY_TEST_UDID" \
  -only-testing:NativeIntentTests/AccessibilityVoiceOverTests \
  -parallel-testing-enabled NO -resultBundlePath /tmp/currency-voiceover.xcresult \
  2>&1 | xcbeautify
```

This bounded speech probe does not verify activation or complete user journeys.
It does not establish whole-app VoiceOver support, pronunciation, Voice Control,
widgets, or watchOS support. Service or speech errors fail the test.
