import Foundation
import Testing
@testable import ReclaimCore

struct ReclaimTests {
  @Test
  func findsKnownLocationsWithoutDoubleCountingOrTouchingAppData() async throws {
    let home = try FixtureHome()
    defer { home.remove() }

    let findings = await Cleaner(home: home.url, runningApps: ["com.running.app", "com.google.Chrome"], fullDiskAccess: true).scan()
    let byTitle = Dictionary(uniqueKeysWithValues: findings.map { ($0.title, $0) })

    // Nested rule owns its folder; the outer rule skips it.
    // Grouped: one row for the whole folder, removing what's inside it.
    #expect(byTitle["Homebrew"]?.targets.flatMap(\.paths).map(\.lastPathComponent) == ["bottle.tar.gz"])
    #expect(byTitle["Homebrew"]?.safety == .safe)
    let userCaches = Set(byTitle["Your apps"]?.targets.map(\.url.lastPathComponent) ?? [])
    #expect(userCaches == ["com.example.app"])  // no Homebrew, protected CloudKit, or running apps

    #expect(byTitle["web"]?.category == .nodeModules)
    #expect(byTitle["web"]?.preselected == false)
    #expect(byTitle["Game · rebuildable files"]?.targets.map(\.url.lastPathComponent) == ["Library"])
    #expect(byTitle["Game · exported builds"]?.safety == .checkFirst)
    #expect(byTitle["Game · exported builds"]?.movesToTrash == true)
    #expect(Set(findings.map(\.id)).count == findings.count)
    #expect(!findings.contains { $0.location.path.contains("Application Support") })
    #expect(byTitle["Homebrew"]?.bytes ?? 0 >= 4096)
  }

  @Test
  func withoutFullDiskAccessSkipsPrivacyProtectedLocations() async throws {
    let home = try FixtureHome()
    defer { home.remove() }

    let findings = await Cleaner(home: home.url, runningApps: [], fullDiskAccess: false).scan()
    #expect(!findings.contains { $0.location.path.contains("/Documents/") || $0.category == .trash })
    #expect(findings.contains { $0.title == "Your apps" })
  }

  @Test
  func leftoversOnlyForRemovedAppsAndBrokenLoginItems() throws {
    let home = try FixtureHome()
    defer { home.remove() }
    let lib = home.url.appendingPathComponent("Library")
    for path in ["Containers/com.gone.app/data", "Containers/com.kept.app/data", "Containers/com.kept.app.ShareExtension/data",
                 "Containers/com.apple.Notes/data", "Group Containers/ABCDE12345.group.com.kept.shared/data",
                 "Group Containers/group.com.gone.shared/data", "Group Containers/243LU875E5.groups.com.apple.podcasts/data"] {
      try home.write(lib.appendingPathComponent(path))
    }
    let agent = lib.appendingPathComponent("LaunchAgents/com.me.monitor.plist")
    try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (["Label": "com.me.monitor", "ProgramArguments": ["/nonexistent/monitor"]] as NSDictionary).write(to: agent)

    let cleaner = Cleaner(home: home.url, runningApps: [], fullDiskAccess: true)
    let found = Set(cleaner.findLeftovers(apps: InstalledApps(ids: ["com.kept.app"])).flatMap(\.targets).map(\.url.lastPathComponent))
    #expect(found == ["com.gone.app", "group.com.gone.shared", "com.me.monitor.plist"])
  }

  @Test
  func oldPluginVersionsKeepTheOneInUse() throws {
    let home = try FixtureHome()
    defer { home.remove() }
    let cache = home.url.appendingPathComponent(".claude/plugins/cache/market/tool")
    for version in ["old", "current"] { try home.write(cache.appendingPathComponent("\(version)/plugin.json")) }
    let old = cache.appendingPathComponent("old")
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)], ofItemAtPath: old.path)
    let json = ["plugins": ["tool@market": [["installPath": cache.appendingPathComponent("current").path]]]]
    try JSONSerialization.data(withJSONObject: json).write(to: home.url.appendingPathComponent(".claude/plugins/installed_plugins.json"))

    let targets = Cleaner(home: home.url, runningApps: [], fullDiskAccess: true).oldPluginVersions().flatMap(\.targets)
    #expect(targets.map(\.url) == [old])
  }

  @Test
  func duplicatesIgnoreClonesAndKeepTheOldest() throws {
    let home = try FixtureHome()
    defer { home.remove() }
    let original = home.url.appendingPathComponent("Documents/report.pdf")
    let copy = home.url.appendingPathComponent("Downloads/report.pdf")
    let clone = home.url.appendingPathComponent("Desktop/report clone.pdf")
    try home.write(original, bytes: 8192)
    try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: original.path)
    try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contentsOf: original).write(to: copy)  // same bytes, separate write: a real second copy
    try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: original, to: clone)  // APFS clone: shares blocks

    let found = Cleaner(home: home.url, runningApps: [], fullDiskAccess: true).findDuplicates(minimumBytes: 1024)
    #expect(found.count == 1)
    #expect(found.first?.location.lastPathComponent == "report.pdf")
    #expect(found.first?.targets.map { $0.url.resolvingSymlinksInPath().path } == [copy.resolvingSymlinksInPath().path])
  }

  @Test
  func uninstallPlanFindsFilesByBundleID() async throws {
    let home = try FixtureHome()
    defer { home.remove() }
    let app = home.url.appendingPathComponent("Applications/Tool.app")
    let lib = home.url.appendingPathComponent("Library")
    for path in ["Application Support/com.maker.tool/db", "Caches/com.maker.tool/c", "Preferences/com.maker.tool.plist",
                 "Containers/com.maker.tool.Widget/data", "Application Support/Tool/data", "Caches/com.maker.other/c"] {
      try home.write(lib.appendingPathComponent(path))
    }
    try home.write(app.appendingPathComponent("Contents/MacOS/Tool"))

    let plan = await Cleaner(home: home.url, runningApps: [], fullDiskAccess: true)
      .uninstallPlan(for: InstalledApp(url: app, name: "Tool", bundleID: "com.maker.tool"))
    let byTitle = Dictionary(uniqueKeysWithValues: plan.map { ($0.title, Set($0.targets.map(\.url.lastPathComponent))) })
    #expect(byTitle["Tool"] == ["Tool.app", "com.maker.tool", "com.maker.tool.plist", "com.maker.tool.Widget"])
    #expect(byTitle["Possibly related"] == ["Tool"])
  }

  @Test
  func partlyFailedCleanCountsWhatWasRemoved() async throws {
    let home = try FixtureHome()
    defer { home.remove() }
    let locked = home.url.appendingPathComponent("Library/Caches/com.example.app/locked")
    try home.write(locked.appendingPathComponent("kept.bin"), bytes: 4096)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

    let findings = await Cleaner(home: home.url, runningApps: [], fullDiskAccess: true).scan().filter { $0.title == "Your apps" }
    let before = findings.reduce(Int64(0)) { $0 + $1.bytes }
    let result = Cleaner.clean(findings)

    #expect(!result.failures.isEmpty)
    #expect(result.freedBytes > 0)  // the removable files still count
    #expect(result.freedBytes < before)  // the locked file doesn't
  }

  @Test
  func friendlyNames() {
    #expect(friendlyName("MyApp-bxkqzyrcgqlmnbfqnmgmyfxkdvkh", appID: nil) == "MyApp")
    #expect(friendlyName("org.swift.swiftpm", appID: nil) == "swiftpm")
    #expect(friendlyName("com.apple.finder", appID: "com.apple.finder") == "Finder")
  }

  @Test
  func cleanRemovesTargetsButKeepsTheFolder() async throws {
    let home = try FixtureHome()
    defer { home.remove() }

    let caches = home.url.appendingPathComponent("Library/Caches")
    let kept = caches.appendingPathComponent("com.running.app")
    let findings = await Cleaner(home: home.url, runningApps: [], fullDiskAccess: true).scan()
      .filter { $0.title == "Your apps" }
      .map { finding in finding.only(Set(finding.targets.map(\.url)).subtracting([kept])) }
    let result = Cleaner.clean(findings)

    #expect(result.failures.isEmpty)
    #expect(result.freedBytes > 0)
    #expect(FileManager.default.fileExists(atPath: caches.path))
    #expect(FileManager.default.fileExists(atPath: kept.path))  // unselected item survives
    #expect(!FileManager.default.fileExists(atPath: caches.appendingPathComponent("com.example.app").path))
    #expect(FileManager.default.fileExists(atPath: caches.appendingPathComponent("CloudKit").path))
  }
}

private struct FixtureHome {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

  init() throws {
    for path in [
      "Library/Caches/Homebrew/bottle.tar.gz",
      "Library/Caches/com.example.app/data",
      "Library/Caches/com.running.app/data",
      "Library/Caches/CloudKit/state",
      "Library/Caches/Google/Chrome/cache",
      "Library/Application Support/Electron/node_modules/x/index.js",
      "Library/Application Support/Electron/package.json",
      "Projects/web/package.json",
      "Documents/app/package.json",
      "Documents/app/node_modules/x/index.js",
      ".Trash/old.txt",
      "Projects/web/node_modules/left-pad/index.js",
      "Projects/Game/ProjectSettings/ProjectVersion.txt",
      "Projects/Game/Assets/a.png",
      "Projects/Game/Library/ArtifactDB",
      "Projects/Game/Builds/Game.app.zip",
    ] {
      let file = url.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(repeating: 1, count: 4096).write(to: file)
    }
  }

  func write(_ file: URL, bytes: Int = 4096) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).write(to: file)
  }

  func remove() { try? FileManager.default.removeItem(at: url) }
}
