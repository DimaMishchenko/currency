import Conversion
import ExchangeRates
import Foundation
import Onboarding

/// Composes real independent stores only within regression fixtures.
struct OnboardingTestStore {
  let directory: URL
  var progress: OnboardingProgressStore { OnboardingProgressStore(directory: directory) }
  var conversion: ConversionStore { ConversionStore(directory: directory) }
  var rates: RateStore { RateStore(directory: directory) }
  func input() -> ConverterState { conversion.input() }
  func loadRates() -> RateSnapshot { rates.loadRates() }
  func onboardingProgress() -> OnboardingProgress? { progress.load() }
  func saveOnboardingProgress(_ value: OnboardingProgress) throws { try progress.save(value) }
  @discardableResult
  func updateInput(_ action: (inout ConverterState) throws -> Void) throws -> ConverterState {
    try conversion.updateInput(action)
  }
}

@MainActor
struct FixtureConfiguration {
  var loadingDelay: Duration = .milliseconds(1200)
  var deadline: Duration = .seconds(12)
  var now: () -> Date = { .now }
  var beforeSave: ((OnboardingModel.SaveError) throws -> Void)?
}

/// Faults are supplied through the production operation closures, never through model hooks.
@MainActor
func makeModel(
  store: OnboardingTestStore, service: RateService = RateService(),
  configuration: FixtureConfiguration = .init()
) -> OnboardingModel {
  let dependencies = OnboardingDependencies(
    loadProgress: { store.onboardingProgress() },
    saveProgress: { progress in
      try configuration.beforeSave?(progress.completed ? .completion : .draft)
      try store.saveOnboardingProgress(progress)
    },
    readInput: { store.input() },
    editInput: { edit in
      try configuration.beforeSave?(.selection)
      try store.updateInput(edit)
    },
    readRates: { store.loadRates() },
    saveRates: { snapshot, now in
      try configuration.beforeSave?(.rates)
      return try store.rates.saveBootstrapRates(snapshot, now: now)
    },
    bootstrap: { previous, now in await service.bootstrap(previous: previous, now: now) },
    now: configuration.now
  )
  return OnboardingModel(
    dependencies: dependencies,
    configuration: .init(loadingDelay: configuration.loadingDelay, deadline: configuration.deadline)
  )
}
