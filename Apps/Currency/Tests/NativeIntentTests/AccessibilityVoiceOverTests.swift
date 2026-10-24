import XCTest

@MainActor
final class AccessibilityVoiceOverTests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "com.dimasike.currency")
  private var transcript: [String] = []

  override func setUp() {
    continueAfterFailure = false
  }

  func testVoiceOverConverterSpeechAndTraversal() throws {
    try withVoiceOver {
      try focus(containing: "Options")
      let previous = try XCUIDevice.shared.voiceOverService.moveBackward().utterance
      record("Backward: \(previous)")
      XCTAssertTrue(previous.contains("Widgets"))
      let restored = try XCUIDevice.shared.voiceOverService.moveForward().utterance
      record("Forward: \(restored)")
      XCTAssertTrue(restored.contains("Options"))
      attachScreenshot("VoiceOver focused Options")
      try focus(containing: "Edit amount in EUR")
      let amount = try XCUIDevice.shared.voiceOverService.currentSpeech().utterance
      XCTAssertTrue(amount.contains("1"), "VoiceOver must speak the seeded source amount")
      attachScreenshot("VoiceOver reads source amount")
    }
  }

  private func withVoiceOver(_ body: () throws -> Void) throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    let wasEnabled = voiceOver.isEnabled
    addTeardownBlock {
      let attachment = XCTAttachment(string: self.transcript.joined(separator: "\n"))
      attachment.name = "VoiceOver speech transcript"
      attachment.lifetime = .keepAlways
      self.add(attachment)
      if wasEnabled {
        if !voiceOver.isEnabled { try voiceOver.enable() }
      } else if voiceOver.isEnabled {
        try voiceOver.disable()
      }
    }
    app.launchArguments = [
      "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-CurrencyE2E",
      "-CurrencyE2EState", "ready-converter"
    ]
    app.launch()
    XCTAssertTrue(app.buttons["converter.widgets"].waitForExistence(timeout: 10))
    if !wasEnabled { try voiceOver.enable() }
    XCTAssertTrue(voiceOver.isEnabled)
    let initial = try initialSpeech()
    record("Initial: \(initial)")
    XCTAssertFalse(initial.isEmpty)
    try body()
  }

  private func initialSpeech() throws -> String {
    let deadline = Date().addingTimeInterval(10)
    while true {
      do {
        return try XCUIDevice.shared.voiceOverService.currentSpeech().utterance
      } catch {
        let serviceError = error as NSError
        guard serviceError.domain == "com.apple.xctest.voiceoverservice",
          serviceError.code == 3, Date() < deadline
        else { throw error }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }
  }

  private func focus(containing text: String, maximumMoves: Int = 30) throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    for index in 0...maximumMoves {
      let speech = try voiceOver.currentSpeech().utterance
      record("Focus: \(speech)")
      if speech.localizedCaseInsensitiveContains(text) { return }
      if index < maximumMoves {
        record("Forward: \(try voiceOver.moveForward().utterance)")
      }
    }
    XCTFail("VoiceOver did not reach \(text) within \(maximumMoves) moves")
  }

  private func record(_ speech: String) {
    transcript.append(speech)
    XCTContext.runActivity(named: speech) { _ in }
  }

  private func attachScreenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
