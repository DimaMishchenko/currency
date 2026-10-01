import ProjectDescription

let teamID = "77X75EH6F4"
let supportedLanguages: Plist.Value = [
  "en", "zh-Hans", "ja", "es", "de", "fr", "pt-BR", "ko", "zh-Hant", "it", "tr", "ru", "uk", "et"
]
let appProfile = Environment.currencyAppProfileUuid.getString(default: "")
let widgetProfile = Environment.currencyWidgetProfileUuid.getString(default: "")
let currencyUnitTestTargets: [TargetReference] = [
  "DesignSystemPackageTests", "ExchangeRatesPackageTests", "LocalCurrencyPackageTests",
  "ConversionPackageTests", "WidgetsPackageTests", "HomePackageTests",
  "OnboardingPackageTests", "CurrencyDetailsPackageTests", "SettingsPackageTests",
  "LocationOnboardingPackageTests", "WidgetOnboardingPackageTests",
  "CurrencyApplicationTests", "ForegroundRefreshTests", "AppearancePreferencesTests",
  "WidgetIntegrationTests", "ApplicationIntegrationTests"
]

func releaseSigning(profile: String) -> Settings? {
  guard !profile.isEmpty else { return nil }
  return .settings(configurations: [
    .release(
      name: "Release",
      settings: [
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": "Apple Distribution",
        "DEVELOPMENT_TEAM": .string(teamID),
        "PROVISIONING_PROFILE_SPECIFIER": .string(profile)
      ])
  ])
}

let project = Project(
  name: "Currency", organizationName: "dimasike",
  settings: .settings(base: [
    "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": .string(teamID), "MARKETING_VERSION": "1.0", "SWIFT_VERSION": "6.0",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "TARGETED_DEVICE_FAMILY": "1,2"
  ]),
  targets: [
    .target(
      name: "NativeIntentTests", destinations: .iOS, product: .uiTests,
      bundleId: "com.dimasike.currency.nativeintenttests", deploymentTargets: .iOS("27.0"),
      infoPlist: .default, buildableFolders: ["App/Tests/NativeIntentTests"],
      dependencies: [.target(name: "Currency")],
      settings: .settings(base: [
        "FRAMEWORK_SEARCH_PATHS": "$(inherited) $(PLATFORM_DIR)/Developer/Library/Frameworks"
      ])),
    .target(
      name: "CurrencyApplication", destinations: .iOS, product: .staticFramework,
      bundleId: "com.dimasike.currency.currencyapplication", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/CurrencyApplication/Sources"],
      dependencies: [
        .external(name: "Home"), .external(name: "Onboarding"),
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "LocalCurrency")
      ]),
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
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Currency Widgets",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CFBundleLocalizations": supportedLanguages,
        "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
        "NSWidgetWantsLocation": true
      ]),
      buildableFolders: ["App/Widgets/Sources", "App/Widgets/Resources"],
      entitlements: .file(path: "App/Widgets/Currency.entitlements"),
      dependencies: [
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "ExchangeRatesUI"), .external(name: "LocalCurrency"),
        .external(name: "Widgets"), .external(name: "WidgetsUI")
      ],
      settings: releaseSigning(profile: widgetProfile)),
    .target(
      name: "Currency", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CFBundleLocalizations": supportedLanguages,
        "UIPrefersShowingLanguageSettings": true,
        "ITSAppUsesNonExemptEncryption": false,
        "CFBundleURLTypes": [["CFBundleURLSchemes": ["currency"]]],
        "NSLocationDefaultAccuracyReduced": true,
        "NSLocationWhenInUseUsageDescription":
          "Find your country’s currency and refresh it daily while the app or widgets are in use. Only the country and currency are saved.",
        "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": true],
        "UILaunchScreen": [:],
        "UISupportedInterfaceOrientations": [
          "UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft",
          "UIInterfaceOrientationLandscapeRight"
        ]
      ]),
      buildableFolders: ["App/Sources", "App/Resources"],
      entitlements: .file(path: "App/Configuration/Currency.entitlements"),
      dependencies: [
        .external(name: "Conversion"), .external(name: "CurrencyDetails"),
        .external(name: "CurrencyDetailsUI"), .external(name: "DesignSystem"),
        .external(name: "ExchangeRates"), .external(name: "ExchangeRatesUI"),
        .external(name: "Home"), .external(name: "HomeUI"),
        .external(name: "LocalCurrency"), .external(name: "LocationOnboarding"),
        .external(name: "LocationOnboardingUI"), .external(name: "Onboarding"),
        .external(name: "OnboardingUI"), .external(name: "Settings"),
        .external(name: "SettingsUI"), .external(name: "WidgetOnboarding"),
        .external(name: "WidgetOnboardingUI"), .target(name: "AppearancePreferences"),
        .target(name: "CurrencyApplication"), .target(name: "ForegroundRefresh"),
        .target(name: "CurrencyWidgets")
      ],
      settings: releaseSigning(profile: appProfile)),
    .target(
      name: "DesignSystemPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.designsystempackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["DesignSystem/Tests"],
      dependencies: [.external(name: "DesignSystem")]),
    .target(
      name: "ExchangeRatesPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.exchangeratespackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/ExchangeRates/Tests"],
      dependencies: [.external(name: "ExchangeRates"), .external(name: "ExchangeRatesUI")]),
    .target(
      name: "LocalCurrencyPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.localcurrencypackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/LocalCurrency/Tests"],
      dependencies: [.external(name: "LocalCurrency")]),
    .target(
      name: "ConversionPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.conversionpackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/Conversion/Tests"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "LocalCurrency")
      ]),
    .target(
      name: "WidgetsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetspackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/Widgets/Tests"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "LocalCurrency"), .external(name: "Widgets")
      ]),
    .target(
      name: "HomePackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.homepackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Home/Tests"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "Home"), .external(name: "HomeUI"), .external(name: "LocalCurrency")
      ]),
    .target(
      name: "OnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.onboardingpackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Onboarding/Tests"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "Onboarding")
      ]),
    .target(
      name: "CurrencyDetailsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.currencydetailspackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/CurrencyDetails/Tests"],
      dependencies: [.external(name: "CurrencyDetails"), .external(name: "ExchangeRates")]),
    .target(
      name: "SettingsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.settingspackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Settings/Tests"],
      dependencies: [.external(name: "ExchangeRates"), .external(name: "Settings")]),
    .target(
      name: "LocationOnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.locationonboardingpackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/LocationOnboarding/Tests"],
      dependencies: [.external(name: "LocalCurrency"), .external(name: "LocationOnboarding")]),
    .target(
      name: "WidgetOnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetonboardingpackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/WidgetOnboarding/Tests"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "WidgetOnboarding"), .external(name: "WidgetOnboardingUI"),
        .external(name: "Widgets"), .external(name: "WidgetsUI")
      ]),
    .target(
      name: "CurrencyApplicationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.currencyapplicationtests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["App/Modules/CurrencyApplication/Tests"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "LocalCurrency"),
        .external(name: "ExchangeRates"), .external(name: "Home"),
        .external(name: "Onboarding"), .target(name: "CurrencyApplication")
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
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "ExchangeRatesUI"), .external(name: "LocalCurrency"),
        .external(name: "Widgets"), .external(name: "WidgetsUI")
      ]),
    .target(
      name: "WidgetsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.widgetsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Domain/Widgets/HarnessApp"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "ExchangeRates"),
        .external(name: "LocalCurrency"), .external(name: "Widgets"),
        .external(name: "WidgetsUI")
      ]),
    .target(
      name: "HomeHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.homeharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/Home/HarnessApp"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "DesignSystem"),
        .external(name: "ExchangeRates"), .external(name: "Home"), .external(name: "HomeUI"),
        .external(name: "LocalCurrency")
      ]),
    .target(
      name: "OnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.onboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "UILaunchScreen": [:], "CFBundleLocalizations": supportedLanguages
      ]),
      buildableFolders: ["Features/Onboarding/HarnessApp"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "DesignSystem"),
        .external(name: "ExchangeRates"), .external(name: "Onboarding"),
        .external(name: "OnboardingUI"), .external(name: "WidgetOnboarding"),
        .external(name: "WidgetOnboardingUI")
      ]),
    .target(
      name: "CurrencyDetailsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.currencydetailsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/CurrencyDetails/HarnessApp"],
      dependencies: [
        .external(name: "CurrencyDetails"), .external(name: "CurrencyDetailsUI"),
        .external(name: "DesignSystem"), .external(name: "ExchangeRates")
      ]),
    .target(
      name: "SettingsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.settingsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/Settings/HarnessApp"],
      dependencies: [
        .external(name: "DesignSystem"), .external(name: "ExchangeRates"),
        .external(name: "Settings"), .external(name: "SettingsUI")
      ]),
    .target(
      name: "LocationOnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.locationonboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/LocationOnboarding/HarnessApp"],
      dependencies: [
        .external(name: "DesignSystem"), .external(name: "LocalCurrency"),
        .external(name: "LocationOnboarding"), .external(name: "LocationOnboardingUI")
      ]),
    .target(
      name: "WidgetOnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.widgetonboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/WidgetOnboarding/HarnessApp"],
      dependencies: [
        .external(name: "Conversion"), .external(name: "DesignSystem"),
        .external(name: "WidgetOnboarding"), .external(name: "WidgetOnboardingUI")
      ]),
    .target(
      name: "ApplicationIntegrationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.applicationintegrationtests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      sources: [
        "App/Tests/ApplicationIntegrationTests/**.swift",
        "App/Sources/Composition/**.swift", "App/Sources/SystemActions/**.swift"
      ],
      resources: ["App/Resources/Localizable.xcstrings"],
      dependencies: [
        .external(name: "CurrencyDetailsUI"), .external(name: "CurrencySelectionUI"),
        .external(name: "ExchangeRates"), .external(name: "ExchangeRatesUI"),
        .external(name: "HomeUI"), .external(name: "LocationOnboardingUI"),
        .external(name: "OnboardingUI"), .external(name: "SettingsUI"),
        .external(name: "WidgetOnboardingUI"), .external(name: "WidgetsUI"),
        .external(name: "Conversion"), .external(name: "Home"),
        .external(name: "CurrencyDetails"), .external(name: "LocalCurrency"),
        .external(name: "LocationOnboarding"),
        .external(name: "Onboarding"), .external(name: "Settings"),
        .target(name: "AppearancePreferences"), .target(name: "CurrencyApplication"),
        .target(name: "ForegroundRefresh")
      ])
  ],
  schemes: [
    .scheme(
      name: "NativeIntentTests", shared: true,
      buildAction: .buildAction(targets: ["Currency", "NativeIntentTests"]),
      testAction: .targets(["NativeIntentTests"], expandVariableFromTarget: "Currency")),
    .scheme(
      name: "CurrencyHarnesses", shared: true,
      buildAction: .buildAction(targets: [
        "WidgetsHarness", "HomeHarness", "OnboardingHarness", "CurrencyDetailsHarness",
        "SettingsHarness", "LocationOnboardingHarness", "WidgetOnboardingHarness"
      ])),
    .scheme(
      name: "CurrencyTests", shared: true,
      buildAction: .buildAction(targets: ["Currency", "CurrencyWidgets"] + currencyUnitTestTargets),
      testAction: .targets(
        currencyUnitTestTargets.map {
          .testableTarget(target: $0, parallelization: .swiftTestingOnly)
        }))
  ],
  additionalFiles: ["README.md", "Documentation/**"]
)
