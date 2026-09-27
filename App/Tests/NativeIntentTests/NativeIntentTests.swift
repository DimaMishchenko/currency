import AppIntents
import AppIntentsTesting
import XCTest

@MainActor
final class NativeIntentTests: XCTestCase {
  let definitions = IntentDefinitions(bundleIdentifier: "com.dimasike.currency")

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      let app = XCUIApplication(bundleIdentifier: "com.dimasike.currency")
      app.launch()
      for _ in 0..<6 {
        let primary = app.buttons["onboarding.primary"]
        guard primary.waitForExistence(timeout: 1) else { break }
        let later = app.buttons["onboarding.later"]
        if later.exists { later.tap() } else { primary.tap() }
      }
      XCTAssertFalse(app.buttons["onboarding.primary"].exists)
    }
  }

  func testExactOutputCanFeedAnotherConversion() async throws {
    let euro = definitions.entities["CurrencyEntity"].makeReference(identifier: "EUR")
    let intent = definitions.intents["ConvertAmountIntent"]
      .makeIntent(
        amount: "0.1234567890123456789012345678", source: euro, destination: euro)
    let result = try await intent.run()
    let value: AnyTransientAppEntity = try result.value
    let exact: String = try value.convertedAmount
    XCTAssertEqual(exact, "0.1234567890123456789012345678")
    let chained = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: exact, source: euro, destination: euro)
    let next = try await chained.run()
    let nextValue: AnyTransientAppEntity = try next.value
    let nextExact: String = try nextValue.convertedAmount
    XCTAssertEqual(nextExact, exact)
  }

  func testCrossCurrencyConversionReturnsReadableOutputOrActionableStatus() async throws {
    let currencies = definitions.entities["CurrencyEntity"]
    let result = try await definitions.intents["ConvertAmountIntent"]
      .makeIntent(
        amount: "100", source: currencies.makeReference(identifier: "USD"),
        destination: currencies.makeReference(identifier: "EUR")
      )
      .run()
    let value: AnyTransientAppEntity = try result.value
    let exact: String? = try value.convertedAmount
    let text: String = try value.resultText
    let status: String = try value.status
    if exact != nil {
      XCTAssertTrue(text.contains("≈") && text.contains("🇺🇸") && text.contains("🇪🇺"))
    } else {
      XCTAssertFalse(status.isEmpty)
    }
  }

  func testConversionsResolveAndRunAfterAppTerminationWithoutOpeningUI() async throws {
    let app = XCUIApplication(bundleIdentifier: "com.dimasike.currency")
    let currencies = definitions.entities["CurrencyEntity"]
    let euro = currencies.makeReference(identifier: "EUR")
    let dollar = currencies.makeReference(identifier: "USD")
    app.terminate()
    XCTAssertEqual(app.state, .notRunning)
    let choices = try await currencies.entities(matching: "eur")
    XCTAssertTrue(identifiers(choices).contains("EUR"))
    let converted = try await definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: "100", source: euro, destination: dollar).run()
    let value: AnyTransientAppEntity = try converted.value
    let code: String = try value.currency
    XCTAssertEqual(code, "USD")
    XCTAssertNotEqual(app.state, .runningForeground)
    app.terminate()
    let mine = try await definitions.intents["ConvertToMyCurrenciesIntent"]
      .makeIntent(amount: "100", source: euro).run()
    let values: [AnyTransientAppEntity] = try mine.value
    XCTAssertFalse(values.isEmpty)
    XCTAssertNotEqual(app.state, .runningForeground)
  }

  func testNumberInputCoercionAndCommaDecimal() async throws {
    let euro = definitions.entities["CurrencyEntity"].makeReference(identifier: "EUR")
    let number = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: 12.5, source: euro, destination: euro)
    let result = try await number.run()
    let value: AnyTransientAppEntity = try result.value
    let exact: String = try value.convertedAmount
    XCTAssertEqual(exact, "12.5")
    let comma = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: "12,5", source: euro, destination: euro)
    let commaResult = try await comma.run()
    let commaValue: AnyTransientAppEntity = try commaResult.value
    let commaExact: String = try commaValue.convertedAmount
    XCTAssertEqual(commaExact, "12.5")
    let larger = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: 1234.56, source: euro, destination: euro)
    let largerResult = try await larger.run()
    let largerValue: AnyTransientAppEntity = try largerResult.value
    let largerExact: String = try largerValue.convertedAmount
    XCTAssertEqual(largerExact, "1234.56")
    let integer = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: 1234, source: euro, destination: euro)
    let integerResult = try await integer.run()
    let integerValue: AnyTransientAppEntity = try integerResult.value
    let integerExact: String = try integerValue.convertedAmount
    XCTAssertEqual(integerExact, "1234")
    let commaText = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: "1,234", source: euro, destination: euro)
    let commaTextResult = try await commaText.run()
    let commaTextValue: AnyTransientAppEntity = try commaTextResult.value
    let decimalExact: String = try commaTextValue.convertedAmount
    XCTAssertEqual(decimalExact, "1.234")
    let tiny = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: 1e-8, source: euro, destination: euro)
    let tinyResult = try await tiny.run()
    let tinyValue: AnyTransientAppEntity = try tinyResult.value
    let tinyExact: String = try tinyValue.convertedAmount
    XCTAssertEqual(tinyExact, "0.00000001")
    let ungrouped = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: "1234,56", source: euro, destination: euro)
    let ungroupedResult = try await ungrouped.run()
    let ungroupedValue: AnyTransientAppEntity = try ungroupedResult.value
    let ungroupedExact: String = try ungroupedValue.convertedAmount
    XCTAssertEqual(ungroupedExact, "1234.56")
  }

  func testGroupedTextFailsRatherThanTakingALossyNumericResolverChain() async throws {
    let euro = definitions.entities["CurrencyEntity"].makeReference(identifier: "EUR")
    let intent = definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: "1,234.56", source: euro, destination: euro)
    do {
      _ = try await intent.run()
      XCTFail("Grouped text must retain the exact text grammar")
    } catch {
      XCTAssertFalse(error.localizedDescription.isEmpty)
    }
  }

  func testAmbiguousSymbolOffersMultipleCurrencies() async throws {
    let dollars = try await definitions.entities["CurrencyEntity"].entities(matching: "$")
    XCTAssertGreaterThan(dollars.count, 1)
  }

  func testRateLookupExposesTheRateAndNativeFiatAmountWithoutDuplicateProperties() async throws {
    let euro = definitions.entities["CurrencyEntity"].makeReference(identifier: "EUR")
    let result = try await definitions.intents["CheckRateIntent"]
      .makeIntent(source: euro, destination: euro).run()
    let value: AnyTransientAppEntity = try result.value
    let rate: String = try value.convertedAmount
    let currency: String = try value.currency
    let monetary: IntentCurrencyAmount = try value.monetaryAmount
    let status: String = try value.status
    XCTAssertEqual(rate, "1")
    XCTAssertEqual(currency, "EUR")
    XCTAssertEqual(monetary.amount, 1)
    XCTAssertEqual(monetary.currencyCode, "EUR")
    XCTAssertTrue(status.isEmpty)
  }

  func testLocalIsQueryableAndLabelsItsResult() async throws {
    let localChoices = try await definitions.entities["CurrencyEntity"]
      .entities(
        matching: "Local currency")
    XCTAssertEqual(localChoices.count, 1)
    let euro = definitions.entities["CurrencyEntity"].makeReference(identifier: "EUR")
    let local = definitions.entities["CurrencyEntity"].makeReference(identifier: "@local")
    let result = try await definitions.intents["ConvertAmountIntent"]
      .makeIntent(amount: "1", source: euro, destination: local).run()
    let value: AnyTransientAppEntity = try result.value
    let resultText: String = try value.resultText
    let status: String = try value.status
    XCTAssertTrue(
      resultText.hasSuffix("(Local)")
        || (resultText == "Local currency" && status.contains("set up location")))
  }

  func testMyCurrenciesReturnsAnOrderedStructuredArray() async throws {
    let euro = definitions.entities["CurrencyEntity"].makeReference(identifier: "EUR")
    let intent = definitions.intents["ConvertToMyCurrenciesIntent"]
      .makeIntent(amount: "1", source: euro)
    let result = try await intent.run()
    let values: [AnyTransientAppEntity] = try result.value
    XCTAssertFalse(values.isEmpty)
    let ids = try values.map { value -> String in try value.resultText }
    XCTAssertEqual(Set(ids).count, ids.count)
    let next = try await intent.run()
    let nextValues: [AnyTransientAppEntity] = try next.value
    let nextIDs = try nextValues.map { value -> String in try value.resultText }
    XCTAssertEqual(ids, nextIDs)
  }

  func testCatalogChoicesAndSearchIncludeUnsavedFiatCryptoAndMetals() async throws {
    let definition = definitions.entities["CurrencyEntity"]
    let all = try await definition.allEntities()
    let suggestions = try await definition.suggestedEntities()
    XCTAssertGreaterThan(all.count, 150)
    XCTAssertEqual(identifiers(all), identifiers(suggestions))
    for (term, id) in [("usd", "USD"), ("eur", "EUR"), ("Bitcoin", "BTC"), ("gold", "XAU")] {
      let matches = try await definition.entities(matching: term)
      XCTAssertTrue(identifiers(matches).contains(id), term)
    }
  }

  func testSpotlightIndexesTheFullCatalogAndCurrencyCodes() async throws {
    let definition = definitions.entities["CurrencyEntity"]
    let catalog = try await definition.allEntities()
    let expected = Set(identifiers(catalog).filter { $0 != "@local" })
    var indexed = Set<String>()
    let deadline = Date().addingTimeInterval(10)
    repeat {
      indexed = Set(identifiers(try await definition.spotlightQuery()))
      if expected.isSubset(of: indexed) { break }
      try await Task.sleep(for: .milliseconds(250))
    } while Date() < deadline
    XCTAssertTrue(expected.isSubset(of: indexed), "Missing: \(expected.subtracting(indexed))")
    for id in ["USD", "EUR", "BTC", "XAU"] {
      let matches = try await definition.spotlightQuery(id.lowercased())
      XCTAssertTrue(identifiers(matches).contains(id), id)
    }
  }

  func testExistingDetailsOpenFromColdAndWarmApp() async throws {
    let app = XCUIApplication(bundleIdentifier: "com.dimasike.currency")
    app.terminate()
    XCTAssertEqual(app.state, .notRunning)
    for id in ["XAU", "JPY"] {
      let target = definitions.entities["CurrencyEntity"].makeReference(identifier: id)
      _ = try await definitions.intents["OpenCurrencyIntent"].makeIntent(target: target).run()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
      XCTAssertTrue(
        app.descendants(matching: .any)["currency.details.\(id)"].firstMatch
          .waitForExistence(timeout: 5))
      let annotations = try await annotationIDs(hidden: false)
      XCTAssertEqual(annotations, [id])
      XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
      app.buttons["Close"].tap()
    }
  }

  func testConverterAnnotationsFollowVisibleContent() async throws {
    let app = XCUIApplication(bundleIdentifier: "com.dimasike.currency")
    let visible = try await annotationIDs(hidden: false)
    XCTAssertGreaterThanOrEqual(visible.count, 2)
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Source currency,")).firstMatch
      .tap()
    let picker = try await annotationIDs(hidden: true)
    XCTAssertTrue(picker.isEmpty, "Hidden converter annotations: \(picker)")
    app.buttons["Close"].tap()
    let restored = try await annotationIDs(hidden: false)
    XCTAssertEqual(restored, visible)
    app.buttons["Options"].tap()
    app.buttons["converter.settings"].tap()
    let hidden = try await annotationIDs(hidden: true)
    XCTAssertTrue(hidden.isEmpty, "Hidden converter annotations: \(hidden)")
  }

  private func annotationIDs(hidden: Bool) async throws -> Set<String> {
    let deadline = Date().addingTimeInterval(5)
    var result = Set<String>()
    repeat {
      let annotations = try await definitions.entities["CurrencyEntity"].viewAnnotations()
      result = Set(annotations.map { $0.entity.identifier.instanceIdentifier })
      if result.isEmpty == hidden { break }
      try await Task.sleep(for: .milliseconds(200))
    } while Date() < deadline
    return result
  }

  private func identifiers(_ entities: [AnyAppEntity]) -> [String] {
    entities.map { $0.identifier.instanceIdentifier }
  }

}
