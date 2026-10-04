import Foundation

extension WatchWidgetPresetIntent {
  init(entry: WatchWidgetEntry, amount: Decimal) {
    self.init()
    key = entry.key; codes = entry.codes
    self.amount = NSDecimalNumber(decimal: amount).stringValue
    initialAmount = entry.initialAmount; kind = entry.style.kind
  }
}

extension WatchWidgetSwapIntent {
  init(entry: WatchWidgetEntry) {
    self.init()
    key = entry.key; codes = entry.codes; initialAmount = entry.initialAmount;
    kind = entry.style.kind
  }
}
