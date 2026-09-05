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
      name: "ConverterFeature",
      destinations: .iOS,
      product: .framework,
      bundleId: "com.dimasike.currency.converterfeature",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["Modules/ConverterFeature/Sources", "Modules/ConverterFeature/Resources"],
      dependencies: [
        .package(product: "ExchangeRatesDynamic", type: .runtimeEmbedded),
        .target(name: "CurrencySupport")
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
        .target(name: "ConverterFeature"),
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
        .target(name: "CurrencySupport")
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
