import ProjectDescription

let ciCache = Environment.currencyCiCache.getString(default: "false") == "true"
let ciCloud = Environment.currencyCiCloud.getString(default: "true") == "true"
let tuist = Tuist(
  fullHandle: ciCloud ? "dimasike/currency" : nil,
  project: .tuist(
    generationOptions: .options(optionalAuthentication: true),
    cacheOptions: .options(profiles: .profiles(default: ciCache ? .allPossible : .onlyExternal))
  )
)
