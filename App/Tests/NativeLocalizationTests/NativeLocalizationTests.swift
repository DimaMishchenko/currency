import XCTest

@MainActor
final class NativeLocalizationTests: XCTestCase {
  private let bundleID = "com.dimasike.currency"
  func testEnglish() {
    verifyLanguages(["en"])
  }

  func testSimplifiedChinese() {
    verifyLanguages(["zh-Hans"])
  }

  func testJapanese() {
    verifyLanguages(["ja"])
  }

  func testKorean() {
    verifyLanguages(["ko"])
  }

  func testTraditionalChinese() {
    verifyLanguages(["zh-Hant"])
  }

  func testSpanish() {
    verifyLanguages(["es"])
  }

  func testGerman() {
    verifyLanguages(["de"])
  }

  func testFrench() {
    verifyLanguages(["fr"])
  }

  func testBrazilianPortuguese() {
    verifyLanguages(["pt-BR"])
  }

  func testItalian() {
    verifyLanguages(["it"])
  }

  func testTurkish() {
    verifyLanguages(["tr"])
  }

  func testRussian() {
    verifyLanguages(["ru"])
  }

  func testUkrainian() {
    verifyLanguages(["uk"])
  }

  func testUkrainianPickerAndHistoryAccessibilityTextSize() {
    let app = launchReadyApp()
    app.terminate()
    app.launchArguments = [
      "-AppleLanguages", "(uk)", "-AppleLocale", "en_US",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
    ]
    app.launch()
    verifyPickerAndHistory(app, language: "uk", requiresMenu: true)
    app.terminate()
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
      verifyPickerAndHistory(app, language: language)
      app.terminate()
      app.launch()
      XCTAssertTrue(app.buttons["converter.options"].waitForExistence(timeout: 10))
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

  private func verifyPickerAndHistory(
    _ app: XCUIApplication, language: String, requiresMenu: Bool = false
  ) {
    guard let titles = controlTitles[language] else {
      XCTFail("Missing native control expectations for \(language)")
      return
    }
    let source = app.buttons["converter.source"]
    XCTAssertTrue(source.waitForExistence(timeout: 10))
    source.tap()
    XCTAssertTrue(app.buttons["currency.picker.close"].waitForExistence(timeout: 5))
    capture(app, name: "currency-picker-\(language)\(requiresMenu ? "-accessibility" : "")")
    selectOption(
      app, identifier: "currency.picker.category", title: titles.crypto,
      requiresMenu: requiresMenu)
    XCTAssertTrue(app.buttons["currency.picker.BTC"].waitForExistence(timeout: 5))
    capture(app, name: "currency-picker-crypto-\(language)\(requiresMenu ? "-accessibility" : "")")
    app.buttons["currency.picker.close"].tap()
    XCTAssertTrue(source.waitForExistence(timeout: 5))
    let codes =
      Locale.commonISOCurrencyCodes + [
        "BTC", "ETH", "SOL", "DOGE", "LTC", "USDC", "USDT", "XRP", "ADA", "AVAX",
        "LINK", "DOT", "BCH", "XLM", "ATOM", "UNI", "ETC", "FIL", "AAVE", "ALGO", "SHIB", "ICP"
      ]
    let amountLabels = codes.map { String(format: titles.editAmount, $0) }
    let amount = app.buttons.matching(NSPredicate(format: "label IN %@", amountLabels)).firstMatch
    XCTAssertTrue(amount.waitForExistence(timeout: 5))
    amount.tap()
    let history = app.buttons["converter.history"]
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    history.tap()
    selectOption(
      app, identifier: "currency.details.historyRange", title: titles.yearToDate,
      requiresMenu: requiresMenu)
    let rate = app.staticTexts["currency.details.rate"]
    XCTAssertTrue(rate.exists)
    XCTAssertGreaterThan(rate.frame.width, 0)
    XCTAssertGreaterThanOrEqual(rate.frame.minX, app.windows.firstMatch.frame.minX)
    XCTAssertLessThanOrEqual(rate.frame.maxX, app.windows.firstMatch.frame.maxX)
    Thread.sleep(forTimeInterval: 1)
    capture(app, name: "currency-history-ytd-\(language)\(requiresMenu ? "-accessibility" : "")")
  }

  private func selectOption(
    _ app: XCUIApplication, identifier: String, title: String, requiresMenu: Bool
  ) {
    let segments = app.segmentedControls[identifier]
    if !requiresMenu && segments.waitForExistence(timeout: 1) {
      let option = segments.buttons[title]
      XCTAssertTrue(option.waitForExistence(timeout: 5))
      option.tap()
      XCTAssertTrue(option.isSelected)
    } else {
      if requiresMenu { XCTAssertFalse(segments.exists) }
      let menu = app.buttons[identifier]
      XCTAssertTrue(menu.waitForExistence(timeout: 5))
      menu.tap()
      let option = app.buttons[title].firstMatch
      XCTAssertTrue(option.waitForExistence(timeout: 5))
      option.tap()
      XCTAssertEqual(menu.value as? String, title)
    }
  }

  private struct ControlTitles {
    let crypto: String
    let yearToDate: String
    let editAmount: String
  }

  private var controlTitles: [String: ControlTitles] {
    [
      "en": ControlTitles(
        crypto: "Cryptocurrencies", yearToDate: "Year to date", editAmount: "Edit amount in %@"),
      "zh-Hans": ControlTitles(crypto: "加密货币", yearToDate: "年初至今", editAmount: "编辑%@金额"),
      "ja": ControlTitles(crypto: "暗号資産", yearToDate: "年初から現在まで", editAmount: "%@の金額を編集"),
      "ko": ControlTitles(crypto: "암호화폐", yearToDate: "올해 초부터 현재까지", editAmount: "%@ 금액 편집"),
      "zh-Hant": ControlTitles(crypto: "加密貨幣", yearToDate: "年初至今", editAmount: "編輯%@金額"),
      "es": ControlTitles(
        crypto: "Criptomonedas", yearToDate: "Desde el inicio del año",
        editAmount: "Editar importe en %@"),
      "de": ControlTitles(
        crypto: "Kryptowährungen", yearToDate: "Seit Jahresbeginn",
        editAmount: "Betrag in %@ bearbeiten"),
      "fr": ControlTitles(
        crypto: "Cryptomonnaies", yearToDate: "Depuis le début de l’année",
        editAmount: "Modifier le montant en %@"),
      "pt-BR": ControlTitles(
        crypto: "Criptomoedas", yearToDate: "Desde o início do ano",
        editAmount: "Editar valor em %@"),
      "it": ControlTitles(
        crypto: "Criptovalute", yearToDate: "Da inizio anno", editAmount: "Modifica l’importo in %@"
      ),
      "tr": ControlTitles(
        crypto: "Kripto paralar", yearToDate: "Yıl başından beri",
        editAmount: "%@ cinsinden tutarı düzenle"),
      "ru": ControlTitles(
        crypto: "Криптовалюты", yearToDate: "С начала года", editAmount: "Изменить сумму в %@"),
      "uk": ControlTitles(
        crypto: "Криптовалюти", yearToDate: "Від початку року", editAmount: "Змінити суму в %@")
    ]
  }

  private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
