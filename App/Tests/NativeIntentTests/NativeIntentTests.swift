import AppIntents
import AppIntentsTesting
import XCTest

/// Runs the installed executable's extracted intents, without importing copied app declarations.
@MainActor
final class NativeIntentTests: XCTestCase {
  let definitions = IntentDefinitions(bundleIdentifier: "com.dimasike.currency")

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      XCUIApplication(bundleIdentifier: "com.dimasike.currency").launch()
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
      XCTAssertTrue(error.localizedDescription.contains("without grouping"))
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
    XCTAssertTrue(resultText.hasSuffix("(Local)"))
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
}
