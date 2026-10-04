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

func module(name: String, owner: String, dependencies: [String] = []) -> Target {
  let sourcePath = "\(owner)/Sources/\(name)"
  let containsResources = name.hasSuffix("UI")
  return .target(
    name: name, destinations: .iOS, product: .staticFramework,
    bundleId: "com.dimasike.currency.\(name.lowercased())", deploymentTargets: .iOS("26.0"),
    infoPlist: .default,
    sources: containsResources ? .sourceFilesList(globs: [.glob("\(sourcePath)/**.swift")]) : nil,
    resources: containsResources ? .resources([.glob(pattern: "\(sourcePath)/Resources/**")]) : nil,
    buildableFolders: containsResources
      ? []
      : [
        .folder("\(sourcePath)", exceptions: [.exception(excluded: ["README.md"])])
      ],
    dependencies: dependencies.map { .target(name: $0) },
    settings: containsResources
      ? .settings(base: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) SWIFT_PACKAGE"])
      : nil)
}

let modules: [Target] = [
  module(name: "CoordinatedFiles", owner: "Foundation/CoordinatedFiles"),
  module(name: "DesignSystem", owner: "Foundation/DesignSystem"),
  module(name: "ExchangeRates", owner: "Domain/ExchangeRates", dependencies: ["CoordinatedFiles"]),
  module(
    name: "ExchangeRatesUI", owner: "Domain/ExchangeRates",
    dependencies: ["ExchangeRates", "DesignSystem"]),
  module(
    name: "LocalCurrency", owner: "Domain/LocalCurrency",
    dependencies: ["ExchangeRates", "CoordinatedFiles"]),
  module(
    name: "Conversion", owner: "Domain/Conversion",
    dependencies: ["CoordinatedFiles", "ExchangeRates", "LocalCurrency"]),
  module(
    name: "CurrencySelectionUI", owner: "Domain/Conversion",
    dependencies: ["Conversion", "ExchangeRates", "ExchangeRatesUI", "DesignSystem"]),
  module(
    name: "Widgets", owner: "Domain/Widgets",
    dependencies: ["CoordinatedFiles", "ExchangeRates", "LocalCurrency", "Conversion"]),
  module(
    name: "WidgetsUI", owner: "Domain/Widgets",
    dependencies: [
      "Widgets", "ExchangeRates", "ExchangeRatesUI", "LocalCurrency", "Conversion", "DesignSystem"
    ]),
  module(
    name: "Home", owner: "Features/Home",
    dependencies: ["Conversion", "LocalCurrency", "ExchangeRates"]),
  module(
    name: "HomeUI", owner: "Features/Home",
    dependencies: [
      "Home", "Conversion", "ExchangeRates", "CurrencySelectionUI", "ExchangeRatesUI",
      "DesignSystem"
    ]),
  module(
    name: "Onboarding", owner: "Features/Onboarding",
    dependencies: ["CoordinatedFiles", "ExchangeRates", "Conversion"]),
  module(
    name: "OnboardingUI", owner: "Features/Onboarding",
    dependencies: [
      "Onboarding", "ExchangeRatesUI", "DesignSystem", "Conversion", "ExchangeRates",
      "CurrencySelectionUI"
    ]),
  module(
    name: "CurrencyDetails", owner: "Features/CurrencyDetails", dependencies: ["ExchangeRates"]),
  module(
    name: "CurrencyDetailsUI", owner: "Features/CurrencyDetails",
    dependencies: ["CurrencyDetails", "ExchangeRatesUI", "DesignSystem", "ExchangeRates"]),
  module(name: "Settings", owner: "Features/Settings", dependencies: ["ExchangeRates"]),
  module(
    name: "SettingsUI", owner: "Features/Settings",
    dependencies: ["Settings", "ExchangeRates", "ExchangeRatesUI", "DesignSystem"]),
  module(
    name: "LocationOnboarding", owner: "Features/LocationOnboarding",
    dependencies: ["LocalCurrency", "Conversion"]),
  module(
    name: "LocationOnboardingUI", owner: "Features/LocationOnboarding",
    dependencies: ["LocationOnboarding", "ExchangeRatesUI", "DesignSystem"]),
  module(
    name: "WidgetOnboarding", owner: "Features/WidgetOnboarding",
    dependencies: ["Widgets", "Conversion", "ExchangeRates"]),
  module(
    name: "WidgetOnboardingUI", owner: "Features/WidgetOnboarding",
    dependencies: [
      "WidgetOnboarding", "Widgets", "WidgetsUI", "Conversion", "CurrencySelectionUI",
      "ExchangeRates", "ExchangeRatesUI", "DesignSystem"
    ])
]

let project = Project(
  name: "Currency", organizationName: "dimasike",
  settings: .settings(base: [
    "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": .string(teamID), "MARKETING_VERSION": "1.0", "SWIFT_VERSION": "6.0",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "TARGETED_DEVICE_FAMILY": "1,2"
  ]),
  targets: modules + [
    .target(
      name: "NativeIntentTests", destinations: .iOS, product: .uiTests,
      bundleId: "com.dimasike.currency.nativeintenttests", deploymentTargets: .iOS("27.0"),
      infoPlist: .default, buildableFolders: ["Apps/Currency/Tests/NativeIntentTests"],
      dependencies: [.target(name: "Currency")],
      settings: .settings(base: [
        "FRAMEWORK_SEARCH_PATHS": "$(inherited) $(PLATFORM_DIR)/Developer/Library/Frameworks"
      ])),
    .target(
      name: "CurrencyApplication", destinations: .iOS, product: .staticFramework,
      bundleId: "com.dimasike.currency.currencyapplication", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Apps/Currency/Modules/CurrencyApplication/Sources"],
      dependencies: [
        .target(name: "Home"), .target(name: "Onboarding"),
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "LocalCurrency")
      ]),
    .target(
      name: "ForegroundRefresh", destinations: .iOS, product: .staticFramework,
      bundleId: "com.dimasike.currency.foregroundrefresh", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Apps/Currency/Modules/ForegroundRefresh/Sources"],
      dependencies: []),
    .target(
      name: "AppearancePreferences", destinations: .iOS, product: .staticFramework,
      bundleId: "com.dimasike.currency.appearancepreferences", deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["Apps/Currency/Modules/AppearancePreferences/Sources"],
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
      buildableFolders: [
        .folder(
          "AppExtensions/CurrencyWidgets/Sources",
          exceptions: [
            .exception(
              target: "WidgetIntegrationTests",
              included: [
                "Composition/WidgetComposition.swift",
                "Composition/WidgetDependencies.swift",
                "Composition/WidgetInteractionContext.swift",
                "Configuration/CurrencyIconSettings.swift",
                "Configuration/HistorySettings.swift",
                "Configuration/WidgetConfiguration.swift",
                "Intents/KeypadIntent.swift",
                "Timelines/HistoryTimeline.swift",
                "Timelines/WidgetTimeline.swift"
              ])
          ]),
        "AppExtensions/CurrencyWidgets/Resources"
      ],
      entitlements: .file(
        path: "AppExtensions/CurrencyWidgets/Configuration/Currency.entitlements"),
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "ExchangeRatesUI"), .target(name: "LocalCurrency"),
        .target(name: "Widgets"), .target(name: "WidgetsUI")
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
        ],
        "UISupportedInterfaceOrientations~ipad": [
          "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
          "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
        ]
      ]),
      buildableFolders: [
        .folder(
          "Apps/Currency/App/Sources",
          exceptions: [
            .exception(
              target: "ApplicationIntegrationTests",
              included: [
                "Composition/AppComposition.swift",
                "Composition/LocationPermissionRouting.swift",
                "Composition/SystemActionComposition.swift",
                "SystemActions/ConversionIntents.swift",
                "SystemActions/ConversionResultEntity.swift",
                "SystemActions/CurrencyEntity.swift",
                "SystemActions/CurrencySearchIndex.swift",
                "SystemActions/CurrencyShortcuts.swift",
                "SystemActions/OpenCurrencyIntent.swift"
              ])
          ]),
        .folder(
          "Apps/Currency/App/Resources",
          exceptions: [
            .exception(target: "ApplicationIntegrationTests", included: ["Localizable.xcstrings"])
          ])
      ],
      entitlements: .file(path: "Apps/Currency/App/Configuration/Currency.entitlements"),
      dependencies: [
        .target(name: "Conversion"), .target(name: "CurrencyDetails"),
        .target(name: "CurrencyDetailsUI"), .target(name: "DesignSystem"),
        .target(name: "ExchangeRates"), .target(name: "ExchangeRatesUI"),
        .target(name: "Home"), .target(name: "HomeUI"),
        .target(name: "LocalCurrency"), .target(name: "LocationOnboarding"),
        .target(name: "LocationOnboardingUI"), .target(name: "Onboarding"),
        .target(name: "OnboardingUI"), .target(name: "Settings"),
        .target(name: "SettingsUI"), .target(name: "WidgetOnboarding"),
        .target(name: "WidgetOnboardingUI"), .target(name: "AppearancePreferences"),
        .target(name: "CurrencyApplication"), .target(name: "ForegroundRefresh"),
        .target(name: "CurrencyWidgets")
      ],
      settings: releaseSigning(profile: appProfile)),
    .target(
      name: "DesignSystemPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.designsystempackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Foundation/DesignSystem/Tests"],
      dependencies: [.target(name: "DesignSystem")]),
    .target(
      name: "ExchangeRatesPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.exchangeratespackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/ExchangeRates/Tests"],
      dependencies: [.target(name: "ExchangeRates"), .target(name: "ExchangeRatesUI")]),
    .target(
      name: "LocalCurrencyPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.localcurrencypackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/LocalCurrency/Tests"],
      dependencies: [.target(name: "LocalCurrency")]),
    .target(
      name: "ConversionPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.conversionpackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/Conversion/Tests"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "LocalCurrency")
      ]),
    .target(
      name: "WidgetsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetspackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Domain/Widgets/Tests"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "LocalCurrency"), .target(name: "Widgets")
      ]),
    .target(
      name: "HomePackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.homepackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Home/Tests"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "Home"), .target(name: "HomeUI"), .target(name: "LocalCurrency")
      ]),
    .target(
      name: "OnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.onboardingpackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Onboarding/Tests"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "Onboarding")
      ]),
    .target(
      name: "CurrencyDetailsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.currencydetailspackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/CurrencyDetails/Tests"],
      dependencies: [.target(name: "CurrencyDetails"), .target(name: "ExchangeRates")]),
    .target(
      name: "SettingsPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.settingspackagetests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/Settings/Tests"],
      dependencies: [.target(name: "ExchangeRates"), .target(name: "Settings")]),
    .target(
      name: "LocationOnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.locationonboardingpackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/LocationOnboarding/Tests"],
      dependencies: [.target(name: "LocalCurrency"), .target(name: "LocationOnboarding")]),
    .target(
      name: "WidgetOnboardingPackageTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetonboardingpackagetests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Features/WidgetOnboarding/Tests"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "WidgetOnboarding"), .target(name: "WidgetOnboardingUI"),
        .target(name: "Widgets"), .target(name: "WidgetsUI")
      ]),
    .target(
      name: "CurrencyApplicationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.currencyapplicationtests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Apps/Currency/Modules/CurrencyApplication/Tests"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "LocalCurrency"),
        .target(name: "ExchangeRates"), .target(name: "Home"),
        .target(name: "Onboarding"), .target(name: "CurrencyApplication")
      ]),
    .target(
      name: "ForegroundRefreshTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.foregroundrefreshtests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Apps/Currency/Modules/ForegroundRefresh/Tests"],
      dependencies: [.target(name: "ForegroundRefresh")]),
    .target(
      name: "AppearancePreferencesTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.appearancepreferencestests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default, buildableFolders: ["Apps/Currency/Modules/AppearancePreferences/Tests"],
      dependencies: [.target(name: "AppearancePreferences")]),
    .target(
      name: "WidgetIntegrationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.widgetintegrationtests", deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["AppExtensions/CurrencyWidgets/Tests/WidgetIntegrationTests"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "ExchangeRatesUI"), .target(name: "LocalCurrency"),
        .target(name: "Widgets"), .target(name: "WidgetsUI")
      ]),
    .target(
      name: "WidgetsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.widgetsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Domain/Widgets/HarnessApp"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "ExchangeRates"),
        .target(name: "LocalCurrency"), .target(name: "Widgets"),
        .target(name: "WidgetsUI")
      ]),
    .target(
      name: "HomeHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.homeharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/Home/HarnessApp"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "DesignSystem"),
        .target(name: "ExchangeRates"), .target(name: "Home"), .target(name: "HomeUI"),
        .target(name: "LocalCurrency")
      ]),
    .target(
      name: "OnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.onboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "UILaunchScreen": [:], "CFBundleLocalizations": supportedLanguages
      ]),
      buildableFolders: ["Features/Onboarding/HarnessApp"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "DesignSystem"),
        .target(name: "ExchangeRates"), .target(name: "Onboarding"),
        .target(name: "OnboardingUI"), .target(name: "WidgetOnboarding"),
        .target(name: "WidgetOnboardingUI")
      ]),
    .target(
      name: "CurrencyDetailsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.currencydetailsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/CurrencyDetails/HarnessApp"],
      dependencies: [
        .target(name: "CurrencyDetails"), .target(name: "CurrencyDetailsUI"),
        .target(name: "DesignSystem"), .target(name: "ExchangeRates")
      ]),
    .target(
      name: "SettingsHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.settingsharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/Settings/HarnessApp"],
      dependencies: [
        .target(name: "DesignSystem"), .target(name: "ExchangeRates"),
        .target(name: "Settings"), .target(name: "SettingsUI")
      ]),
    .target(
      name: "LocationOnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.locationonboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/LocationOnboarding/HarnessApp"],
      dependencies: [
        .target(name: "DesignSystem"), .target(name: "LocalCurrency"),
        .target(name: "LocationOnboarding"), .target(name: "LocationOnboardingUI")
      ]),
    .target(
      name: "WidgetOnboardingHarness", destinations: .iOS, product: .app,
      bundleId: "com.dimasike.currency.widgetonboardingharness", deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
      buildableFolders: ["Features/WidgetOnboarding/HarnessApp"],
      dependencies: [
        .target(name: "Conversion"), .target(name: "DesignSystem"),
        .target(name: "WidgetOnboarding"), .target(name: "WidgetOnboardingUI")
      ]),
    .target(
      name: "ApplicationIntegrationTests", destinations: .iOS, product: .unitTests,
      bundleId: "com.dimasike.currency.applicationintegrationtests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["Apps/Currency/Tests/ApplicationIntegrationTests"],
      dependencies: [
        .target(name: "CurrencyDetailsUI"), .target(name: "CurrencySelectionUI"),
        .target(name: "ExchangeRates"), .target(name: "ExchangeRatesUI"),
        .target(name: "HomeUI"), .target(name: "LocationOnboardingUI"),
        .target(name: "OnboardingUI"), .target(name: "SettingsUI"),
        .target(name: "WidgetOnboardingUI"), .target(name: "WidgetsUI"),
        .target(name: "Conversion"), .target(name: "Home"),
        .target(name: "CurrencyDetails"), .target(name: "LocalCurrency"),
        .target(name: "LocationOnboarding"),
        .target(name: "Onboarding"), .target(name: "Settings"),
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
  additionalFiles: [
    "README.md", "LICENSE", "Project.swift", "Tuist.swift", ".gitignore", ".mise.toml",
    ".swift-format", ".github/**/*.yml", ".github/**/*.md", "Documentation/**/*.md",
    "Documentation/**/*.png", "Scripts/**/*.sh", "Scripts/**/*.py",
    "Tuist/Package.swift", "Apps/Currency/README.md", "Apps/Currency/App/Configuration/**",
    "Apps/Currency/Modules/*/README.md", "AppExtensions/CurrencyWidgets/README.md",
    "AppExtensions/CurrencyWidgets/Configuration/**", "Foundation/*/Package.swift",
    "Foundation/*/README.md", "Domain/*/Package.swift", "Domain/*/README.md",
    "Features/*/Package.swift", "Features/*/README.md", "Features/*/.swift-format"
  ]
)
