import ProjectDescription

let project = Project(
  name: "Currency",
  organizationName: "dimasike",
  packages: [
    .local(path: ".")
  ],
  settings: .settings(
    base: [
      "CODE_SIGN_STYLE": "Automatic",
      "SWIFT_VERSION": "6.0",
      "TARGETED_DEVICE_FAMILY": "1,2"
    ]
  ),
  targets: [
    .target(
      name: "CurrencyShared",
      destinations: .iOS,
      product: .staticFramework,
      bundleId: "com.dimasike.currency.shared",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .default,
      buildableFolders: ["CurrencyShared/Sources"],
      dependencies: [
        .package(product: "RateCore")
      ],
      metadata: .metadata(tags: ["tag:layer:shared"])
    ),
    .target(
      name: "CurrencyWidgets",
      destinations: .iOS,
      product: .appExtension,
      bundleId: "com.dimasike.currency.widgets",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .file(path: "Widgets/Info.plist"),
      buildableFolders: ["Widgets/Sources"],
      entitlements: .file(path: "Widgets/Currency.entitlements"),
      dependencies: [
        .package(product: "RateCore"),
        .target(name: "CurrencyShared")
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
      buildableFolders: ["App/Sources"],
      entitlements: .file(path: "App/Currency.entitlements"),
      dependencies: [
        .package(product: "RateCore"),
        .target(name: "CurrencyShared"),
        .target(name: "CurrencyWidgets")
      ],
      metadata: .metadata(tags: [
        "tag:feature:converter",
        "tag:layer:ui"
      ])
    )
  ],
  additionalFiles: [
    "README.md",
    "Documentation/**"
  ]
)
