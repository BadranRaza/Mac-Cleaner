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
    #expect(byTitle["Homebrew"]?.targets.map(\.url.lastPathComponent) == ["bottle.tar.gz"])
    let userCaches = Set(byTitle["User caches"]?.targets.map(\.url.lastPathComponent) ?? [])
    #expect(userCaches == ["com.example.app"])  // no Homebrew, protected CloudKit, or running apps

    #expect(byTitle["web · node_modules"] != nil)
    #expect(byTitle["Game · Unity cache"]?.targets.map(\.url.lastPathComponent) == ["Library"])
    #expect(!findings.contains { $0.location.path.contains("Application Support") })
    #expect(byTitle["Homebrew"]?.bytes ?? 0 >= 4096)
  }

  @Test
  func withoutFullDiskAccessSkipsPrivacyProtectedLocations() async throws {
    let home = try FixtureHome()
    defer { home.remove() }

    let findings = await Cleaner(home: home.url, runningApps: [], fullDiskAccess: false).scan()
    #expect(!findings.contains { $0.location.path.contains("/Documents/") || $0.category == .trash })
    #expect(findings.contains { $0.title == "User caches" })
  }

  @Test
  func cleanRemovesTargetsButKeepsTheFolder() async throws {
    let home = try FixtureHome()
    defer { home.remove() }

    let findings = await Cleaner(home: home.url, runningApps: [], fullDiskAccess: true).scan().filter { $0.title == "User caches" }
    let result = Cleaner.clean(findings)

    #expect(result.failures.isEmpty)
    #expect(result.freedBytes > 0)
    let caches = home.url.appendingPathComponent("Library/Caches")
    #expect(FileManager.default.fileExists(atPath: caches.path))
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
    ] {
      let file = url.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(repeating: 1, count: 4096).write(to: file)
    }
  }

  func remove() { try? FileManager.default.removeItem(at: url) }
}
