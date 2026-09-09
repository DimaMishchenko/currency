import ProjectDescription

let project = Project(
  name: "Currency",
  organizationName: "dimasike",
  packages: [.local(path: ".")],
  settings: .settings(
    base: [
      "CODE_SIGN_STYLE": "Automatic",
      "SWIFT_VERSION": "6.0",
      "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
      "SWIFT_EMIT_LOC_STRINGS": "YES",
      "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
      "TARGETED_DEVICE_FAMILY": "1,2"
    ]
  ),
  targets: [
    .target(
      name: "CurrencySupport",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.shared",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["Modules/CurrencySupport/Sources", "Modules/CurrencySupport/Resources"],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded)
      ],
      metadata: .metadata(tags: ["tag:layer:shared"])
    ),
    .target(
      name: "WidgetPresentation",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.widgetpresentation",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "Modules/WidgetPresentation/Sources", "Modules/WidgetPresentation/Resources"
      ],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport")
      ],
      metadata: .metadata(tags: ["tag:layer:ui", "tag:feature:widgets"])
    ),
    .target(
      name: "CurrencySelectionUI",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.selection",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "Modules/CurrencySelectionUI/Sources", "Modules/CurrencySelectionUI/Resources"
      ],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport")
      ],
      metadata: .metadata(tags: ["tag:layer:ui"])
    ),
    .target(
      name: "WidgetOnboardingFeature",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.widgetonboarding",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "Modules/WidgetOnboardingFeature/Sources", "Modules/WidgetOnboardingFeature/Resources"
      ],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport"),
        .target(name: "CurrencySelectionUI"),
        .target(name: "WidgetPresentation")
      ],
      metadata: .metadata(tags: ["tag:feature:widget-onboarding"])
    ),
    .target(
      name: "LocalCurrencyOnboardingFeature",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.localonboarding",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "Modules/LocalCurrencyOnboardingFeature/Sources",
        "Modules/LocalCurrencyOnboardingFeature/Resources"
      ],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport"),
        .target(name: "CurrencySelectionUI")
      ],
      metadata: .metadata(tags: ["tag:feature:local-currency-onboarding"])
    ),
    .target(
      name: "ConverterFeature",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.converterfeature",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["Modules/ConverterFeature/Sources", "Modules/ConverterFeature/Resources"],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport"),
        .target(name: "CurrencySelectionUI")
      ],
      metadata: .metadata(tags: ["tag:feature:converter"])
    ),
    .target(
      name: "RateDetailsFeature",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.ratedetailsfeature",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "Modules/RateDetailsFeature/Sources", "Modules/RateDetailsFeature/Resources"
      ],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport")
      ],
      metadata: .metadata(tags: ["tag:feature:rate-details"])
    ),
    .target(
      name: "CurrencySupportTests",
      destinations: .iOS,
      product: .unitTests,
      bundleId: "com.dimasike.currency.support.tests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["Modules/CurrencySupport/Tests"],
      dependencies: [
        .target(name: "CurrencySupport"),
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded)
      ]
    ),
    .target(
      name: "CurrencyIntegrationTests",
      destinations: .iOS,
      product: .unitTests,
      bundleId: "com.dimasike.currency.integration.tests",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["App/Tests"],
      dependencies: [
        .target(name: "CurrencySupport"),
        .target(name: "WidgetPresentation"),
        .target(name: "ConverterFeature"),
        .target(name: "WidgetOnboardingFeature"),
        .target(name: "LocalCurrencyOnboardingFeature"),
        .target(name: "CurrencySelectionUI"),
        .target(name: "RateDetailsFeature"),
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded)
      ]
    ),
    .target(
      name: "CurrencyWidgets",
      destinations: .iOS,
      product: .appExtension,
      bundleId: "com.dimasike.currency.widgets",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .file(path: "Widgets/Info.plist"),
      buildableFolders: ["Widgets/Sources", "Widgets/Resources"],
      entitlements: .file(path: "Widgets/Currency.entitlements"),
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport"),
        .target(name: "WidgetPresentation")
      ],
      metadata: .metadata(tags: [
        "tag:feature:widgets",
        "tag:layer:ui"
      ])
    ),
    .target(
      name: "Currency",
      destinations: .iOS,
      product: .app,
      bundleId: "com.dimasike.currency",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .file(path: "App/Info.plist"),
      buildableFolders: ["App/Sources", "App/Resources"],
      entitlements: .file(path: "App/Currency.entitlements"),
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport"),
        .target(name: "CurrencyWidgets"),
        .target(name: "ConverterFeature"),
        .target(name: "WidgetOnboardingFeature"),
        .target(name: "LocalCurrencyOnboardingFeature"),
        .target(name: "CurrencySelectionUI"),
        .target(name: "RateDetailsFeature")
      ],
      metadata: .metadata(tags: [
        "tag:feature:converter",
        "tag:layer:ui"
      ])
    )
  ],
  schemes: [
    .scheme(
      name: "CurrencyIntegrationTests",
      shared: true,
      buildAction: .buildAction(targets: ["CurrencyIntegrationTests"]),
      testAction: .targets(["CurrencyIntegrationTests"])
    )
  ],
  additionalFiles: [
    "README.md",
    "Documentation/**"
  ]
)
