import ProjectDescription

let tuist = Tuist(
  fullHandle: "dimasike/currency",
  project: .tuist(
    generationOptions: .options(optionalAuthentication: true),
    cacheOptions: .options(profiles: .profiles(default: .allPossible))
  )
)
