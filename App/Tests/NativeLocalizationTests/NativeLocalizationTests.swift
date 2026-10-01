import XCTest

@MainActor
final class NativeLocalizationTests: XCTestCase {
  private let bundleID = "com.dimasike.currency"
  func testAsianLanguages() {
    verifyLanguages(["zh-Hans", "ja", "ko", "zh-Hant"])
  }

  func testWesternLanguages() {
    verifyLanguages(["en", "es", "de", "fr", "pt-BR"])
  }

  func testEasternLanguages() {
    verifyLanguages(["it", "tr", "ru", "uk"])
  }

  func testUkrainianWidgetsAndTutorial() {
    let app = launchReadyApp()
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(uk)", "-AppleLocale", "en_US"]
    app.launch()
    app.buttons["converter.widgets"].tap()
    XCTAssertTrue(app.buttons["Додати віджет"].waitForExistence(timeout: 10))
    capture(app, name: "widgets-uk")
    app.buttons["Додати віджет"].tap()
    XCTAssertTrue(app.staticTexts["Утримуйте початковий екран"].waitForExistence(timeout: 5))
    capture(app, name: "widget-tutorial-uk")
  }

  func testUkrainianAccessibilityTextSize() {
    let app = launchReadyApp()
    app.terminate()
    app.launchArguments = [
      "-AppleLanguages", "(uk)", "-AppleLocale", "en_US",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
    ]
    app.launch()
    XCTAssertTrue(app.buttons["converter.widgets"].waitForExistence(timeout: 10))
    capture(app, name: "home-uk-accessibility")
    app.buttons["converter.options"].tap()
    app.buttons["converter.settings"].tap()
    XCTAssertTrue(app.buttons["settings.language"].waitForExistence(timeout: 5))
    capture(app, name: "settings-uk-accessibility")
    app.swipeUp()
    capture(app, name: "settings-uk-accessibility-description")
  }

  private func launchReadyApp() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: bundleID)
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let primary = app.buttons["onboarding.primary"]
    if primary.waitForExistence(timeout: 3) {
      capture(app, name: "onboarding-en")
      for _ in 0..<6 {
        guard primary.waitForExistence(timeout: 5) else { break }
        let later = app.buttons["onboarding.later"]
        if later.exists { later.tap() } else { primary.tap() }
      }
    }
    XCTAssertTrue(app.buttons["converter.widgets"].waitForExistence(timeout: 10))
    return app
  }

  private func verifyLanguages(_ languages: [String]) {
    let app = launchReadyApp()
    app.terminate()
    for language in languages {
      app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", "en_US"]
      app.launch()
      XCTAssertTrue(app.buttons["converter.widgets"].waitForExistence(timeout: 10))
      capture(app, name: "home-\(language)")
      app.buttons["converter.options"].tap()
      app.buttons["converter.settings"].tap()
      let control = app.buttons["settings.language"]
      XCTAssertTrue(control.waitForExistence(timeout: 5))
      XCTAssertFalse(control.label.isEmpty)
      if language != "en" { XCTAssertNotEqual(control.label, "Language") }
      capture(app, name: "settings-\(language)")
      app.terminate()
    }
  }

  func testLanguageOpensSystemSettings() {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.terminate()
    let app = launchReadyApp()
    app.buttons["converter.options"].tap()
    app.buttons["converter.settings"].tap()
    app.buttons["settings.language"].tap()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
  }

  private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
