import Foundation
import Testing
@testable import MacCleanerCore

struct UnityProjectDetectorTests {
  @Test
  func detectsSelectedRootWhenRootIsUnityProject() throws {
    let fixture = try UnityProjectFixture(projectName: "MyGame", hidden: false)
    defer { fixture.cleanup() }

    let detector = UnityProjectDetector()
    let results = detector.scan(
      options: UnityProjectDetectorOptions(
        roots: [fixture.projectURL.path],
        minimumConfidence: 6,
        maxDepth: 2,
        skipHiddenDirectories: true,
        followSymlinks: false
      )
    )

    #expect(results.count == 1)
    #expect(resolvedPath(results.first?.path) == fixture.resolvedProjectPath)
  }

  @Test
  func includesHiddenProjectsWhenRequested() throws {
    let fixture = try UnityProjectFixture(projectName: ".HiddenGame", hidden: true)
    defer { fixture.cleanup() }

    let detector = UnityProjectDetector()
    let results = detector.scan(
      options: UnityProjectDetectorOptions(
        roots: [fixture.rootURL.path],
        minimumConfidence: 6,
        maxDepth: 2,
        skipHiddenDirectories: false,
        followSymlinks: false
      )
    )

    #expect(results.count == 1)
    #expect(resolvedPath(results.first?.path) == fixture.resolvedProjectPath)
  }

  @Test
  func skipsHiddenProjectsByDefault() throws {
    let fixture = try UnityProjectFixture(projectName: ".HiddenGame", hidden: true)
    defer { fixture.cleanup() }

    let detector = UnityProjectDetector()
    let results = detector.scan(
      options: UnityProjectDetectorOptions(
        roots: [fixture.rootURL.path],
        minimumConfidence: 6,
        maxDepth: 2,
        skipHiddenDirectories: true,
        followSymlinks: false
      )
    )

    #expect(results.isEmpty)
  }

  @Test
  func cleanupEngineProducesGenericUnityFinding() throws {
    let fixture = try UnityProjectFixture(projectName: "MyGame", hidden: false)
    defer { fixture.cleanup() }

    let report = CleanupEngine().scanReport(
      options: CleanupScanOptions(
        roots: [fixture.rootURL.path],
        minimumConfidence: 6,
        maxDepth: 2,
        skipHiddenDirectories: true,
        followSymlinks: false
      )
    )

    #expect(report.summary["total"] == 1)
    #expect(report.items.first?.title == "MyGame")
    #expect(report.items.first?.subtitle == "Unity project")
    #expect(report.items.first?.sourceScanner == "Unity")
  }
}

private struct UnityProjectFixture {
  let rootURL: URL
  let projectURL: URL
  let resolvedProjectPath: String

  init(projectName: String, hidden: Bool) throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let projectURL = rootURL.appendingPathComponent(projectName, isDirectory: true)
    let projectSettingsURL = projectURL.appendingPathComponent("ProjectSettings", isDirectory: true)
    let assetsURL = projectURL.appendingPathComponent("Assets", isDirectory: true)

    try FileManager.default.createDirectory(at: projectSettingsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    try "m_EditorVersion: 2022.3.1f1\n".write(
      to: projectSettingsURL.appendingPathComponent("ProjectVersion.txt"),
      atomically: true,
      encoding: .utf8
    )

    self.rootURL = rootURL
    self.projectURL = projectURL
    self.resolvedProjectPath = projectURL.resolvingSymlinksInPath().path
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

private func resolvedPath(_ path: String?) -> String? {
  guard let path else {
    return nil
  }

  return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}
