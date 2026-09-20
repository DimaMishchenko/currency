import ProjectDescription

let project = Project(
  name: "Currency", organizationName: "dimasike",
  packages: [
    .local(path: "DesignSystem"), .local(path: "Domain/ExchangeRates"),
    .local(path: "Domain/LocalCurrency"), .local(path: "Domain/Conversion"),
    .local(path: "Domain/Widgets"), .local(path: "Features/Home"),
    .local(path: "Features/Onboarding"), .local(path: "Features/CurrencyDetails"),
    .local(path: "Features/Settings"), .local(path: "Features/LocationOnboarding"),
    .local(path: "Features/WidgetOnboarding")
  ],
  settings: .settings(base: [
    "CODE_SIGN_STYLE": "Automatic", "SWIFT_VERSION": "6.0",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "TARGETED_DEVICE_FAMILY": "1,2"
  ]),
  targets: [
    .target(
      name: "CurrencyApplication", destinations: .iOS, product: .staticFramework,
      bundleId: "com.dimasike.currency.currencyapplication", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/CurrencyApplication/Sources"],
      dependencies: [.package(product: "Home"), .package(product: "Onboarding")]),
    .target(
      name: "ForegroundRefresh", destinations: .iOS, product: .staticFramework,
      bundleId: "com.dimasike.currency.foregroundrefresh", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/ForegroundRefresh/Sources"],
      dependencies: []),
    .target(
      name: "AppearancePreferences", destinations: .iOS, product: .staticFramework,
      bundleId: "com.dimasike.currency.appearancepreferences", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/AppearancePreferences/Sources"],
      dependencies: []),
    .target(
      name: "CurrencyWidgets", destinations: .iOS, product: .appExtension,
      bundleId: "com.dimasike.currency.widgets", deploymentTargets: .iOS("26.0"),
      infoPlist: .file(path: "App/Widgets/Info.plist"),
      buildableFolders: ["App/Widgets/Sources", "App/Widgets/Resources"],
      entitlements: .file(path: "App/Widgets/Currency.entitlements"),
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "ExchangeRatesUI"), .package(product: "LocalCurrency"),
        .package(product: "Widgets"), .package(product: "WidgetsUI")
      ]),
    .target(
      name: "Currency", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency", deploymentTargets: .iOS("26.0"),
      infoPlist: .file(path: "App/Configuration/Info.plist"),
      buildableFolders: ["App/Sources", "App/Resources"],
      entitlements: .file(path: "App/Configuration/Currency.entitlements"),
      dependencies: [
        .package(product: "Conversion"), .package(product: "CurrencyDetails"),
        .package(product: "CurrencyDetailsUI"), .package(product: "DesignSystem"),
        .package(product: "ExchangeRates"), .package(product: "Home"), .package(product: "HomeUI"),
        .package(product: "LocalCurrency"), .package(product: "LocationOnboarding"),
        .package(product: "LocationOnboardingUI"), .package(product: "Onboarding"),
        .package(product: "OnboardingUI"), .package(product: "Settings"),
        .package(product: "SettingsUI"), .package(product: "WidgetOnboarding"),
        .package(product: "WidgetOnboardingUI"), .target(name: "AppearancePreferences"),
        .target(name: "CurrencyApplication"), .target(name: "ForegroundRefresh"),
        .target(name: "CurrencyWidgets")
      ]),
    .target(
      name: "DesignSystemPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.designsystempackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["DesignSystem/Tests"],
      dependencies: [.package(product: "DesignSystem")]),
    .target(
      name: "ExchangeRatesPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.exchangeratespackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/ExchangeRates/Tests"],
      dependencies: [.package(product: "ExchangeRates"), .package(product: "ExchangeRatesUI")]),
    .target(
      name: "LocalCurrencyPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.localcurrencypackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/LocalCurrency/Tests"],
      dependencies: [.package(product: "LocalCurrency")]),
    .target(
      name: "ConversionPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.conversionpackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/Conversion/Tests"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "LocalCurrency")
      ]),
    .target(
      name: "WidgetsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetspackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/Widgets/Tests"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "LocalCurrency"), .package(product: "Widgets")
      ]),
    .target(
      name: "HomePackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.homepackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Home/Tests"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "Home"), .package(product: "HomeUI"), .package(product: "LocalCurrency")
      ]),
    .target(
      name: "OnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.onboardingpackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Onboarding/Tests"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "Onboarding")
      ]),
    .target(
      name: "CurrencyDetailsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.currencydetailspackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/CurrencyDetails/Tests"],
      dependencies: [.package(product: "CurrencyDetails"), .package(product: "ExchangeRates")]),
    .target(
      name: "SettingsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.settingspackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Settings/Tests"],
      dependencies: [.package(product: "ExchangeRates"), .package(product: "Settings")]),
    .target(
      name: "LocationOnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.locationonboardingpackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/LocationOnboarding/Tests"],
      dependencies: [.package(product: "LocalCurrency"), .package(product: "LocationOnboarding")]),
    .target(
      name: "WidgetOnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetonboardingpackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/WidgetOnboarding/Tests"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "WidgetOnboarding"), .package(product: "WidgetOnboardingUI"),
        .package(product: "Widgets"), .package(product: "WidgetsUI")
      ]),
    .target(
      name: "CurrencyApplicationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.currencyapplicationtests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/CurrencyApplication/Tests"],
      dependencies: [
        .package(product: "ExchangeRates"), .package(product: "Home"),
        .package(product: "Onboarding"), .target(name: "CurrencyApplication")
      ]),
    .target(
      name: "ForegroundRefreshTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.foregroundrefreshtests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/ForegroundRefresh/Tests"],
      dependencies: [.target(name: "ForegroundRefresh")]),
    .target(
      name: "AppearancePreferencesTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.appearancepreferencestests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/AppearancePreferences/Tests"],
      dependencies: [.target(name: "AppearancePreferences")]),
    .target(
      name: "WidgetIntegrationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetintegrationtests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      sources: [
        "App/Tests/WidgetIntegrationTests/**.swift", "App/Widgets/Sources/Composition/**.swift",
        "App/Widgets/Sources/Configuration/**.swift", "App/Widgets/Sources/Intents/**.swift",
        "App/Widgets/Sources/Timelines/**.swift"
      ],
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "ExchangeRatesUI"), .package(product: "LocalCurrency"),
        .package(product: "Widgets"), .package(product: "WidgetsUI")
      ]),
    .target(
      name: "WidgetsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.widgetsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Domain/Widgets/HarnessApp"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "ExchangeRates"),
        .package(product: "LocalCurrency"), .package(product: "Widgets"),
        .package(product: "WidgetsUI")
      ]),
    .target(
      name: "HomeHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.homeharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/Home/HarnessApp"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "DesignSystem"),
        .package(product: "ExchangeRates"), .package(product: "Home"), .package(product: "HomeUI"),
        .package(product: "LocalCurrency")
      ]),
    .target(
      name: "OnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.onboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/Onboarding/HarnessApp"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "DesignSystem"),
        .package(product: "ExchangeRates"), .package(product: "Onboarding"),
        .package(product: "OnboardingUI"), .package(product: "WidgetOnboarding"),
        .package(product: "WidgetOnboardingUI")
      ]),
    .target(
      name: "CurrencyDetailsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.currencydetailsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/CurrencyDetails/HarnessApp"],
      dependencies: [
        .package(product: "CurrencyDetails"), .package(product: "CurrencyDetailsUI"),
        .package(product: "DesignSystem"), .package(product: "ExchangeRates")
      ]),
    .target(
      name: "SettingsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.settingsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/Settings/HarnessApp"],
      dependencies: [
        .package(product: "DesignSystem"), .package(product: "ExchangeRates"),
        .package(product: "Settings"), .package(product: "SettingsUI")
      ]),
    .target(
      name: "LocationOnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.locationonboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/LocationOnboarding/HarnessApp"],
      dependencies: [
        .package(product: "DesignSystem"), .package(product: "LocalCurrency"),
        .package(product: "LocationOnboarding"), .package(product: "LocationOnboardingUI")
      ]),
    .target(
      name: "WidgetOnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.widgetonboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/WidgetOnboarding/HarnessApp"],
      dependencies: [
        .package(product: "Conversion"), .package(product: "DesignSystem"),
        .package(product: "WidgetOnboarding"), .package(product: "WidgetOnboardingUI")
      ]),
    .target(
      name: "ApplicationIntegrationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.applicationintegrationtests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      sources: [
        "App/Tests/ApplicationIntegrationTests/**.swift",
        "App/Sources/Composition/LocationPermissionRouting.swift"
      ],
      dependencies: [
        .package(product: "CurrencyDetailsUI"), .package(product: "CurrencySelectionUI"),
        .package(product: "ExchangeRates"), .package(product: "ExchangeRatesUI"),
        .package(product: "HomeUI"), .package(product: "LocationOnboardingUI"),
        .package(product: "OnboardingUI"), .package(product: "SettingsUI"),
        .package(product: "WidgetOnboardingUI"), .package(product: "WidgetsUI")
      ])
  ],
  schemes: [
    .scheme(
      name: "CurrencyHarnesses", shared: true,
      buildAction: .buildAction(targets: [
        "WidgetsHarness", "HomeHarness", "OnboardingHarness", "CurrencyDetailsHarness",
        "SettingsHarness", "LocationOnboardingHarness", "WidgetOnboardingHarness"
      ])),
    .scheme(
      name: "CurrencyTests", shared: true,
      buildAction: .buildAction(targets: [
        "DesignSystemPackageTests", "ExchangeRatesPackageTests", "LocalCurrencyPackageTests",
        "ConversionPackageTests", "WidgetsPackageTests", "HomePackageTests",
        "OnboardingPackageTests", "CurrencyDetailsPackageTests", "SettingsPackageTests",
        "LocationOnboardingPackageTests", "WidgetOnboardingPackageTests",
        "CurrencyApplicationTests", "ForegroundRefreshTests", "AppearancePreferencesTests",
        "WidgetIntegrationTests", "ApplicationIntegrationTests"
      ]),
      testAction: .targets([
        "DesignSystemPackageTests", "ExchangeRatesPackageTests", "LocalCurrencyPackageTests",
        "ConversionPackageTests", "WidgetsPackageTests", "HomePackageTests",
        "OnboardingPackageTests", "CurrencyDetailsPackageTests", "SettingsPackageTests",
        "LocationOnboardingPackageTests", "WidgetOnboardingPackageTests",
        "CurrencyApplicationTests", "ForegroundRefreshTests", "AppearancePreferencesTests",
        "WidgetIntegrationTests", "ApplicationIntegrationTests"
      ]))
  ],
  additionalFiles: ["README.md", "Documentation/**"]
)
