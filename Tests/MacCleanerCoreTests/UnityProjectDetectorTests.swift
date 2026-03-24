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
        followSymlinks: false
      )
    )

    #expect(results.count == 1)
    #expect(resolvedPath(results.first?.path) == fixture.resolvedProjectPath)
  }

  @Test
  func detectsHiddenProjects() throws {
    let fixture = try UnityProjectFixture(projectName: ".HiddenGame", hidden: true)
    defer { fixture.cleanup() }

    let detector = UnityProjectDetector()
    let results = detector.scan(
      options: UnityProjectDetectorOptions(
        roots: [fixture.rootURL.path],
        minimumConfidence: 6,
        maxDepth: 2,
        followSymlinks: false
      )
    )

    #expect(results.count == 1)
    #expect(resolvedPath(results.first?.path) == fixture.resolvedProjectPath)
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
        followSymlinks: false
      )
    )

    #expect(report.summary.total == 1)
    #expect(report.items.first?.title == "MyGame")
    #expect(report.items.first?.subtitle == "Unity project")
    #expect(report.items.first?.sourceScanner == "Unity")
    #expect(report.items.first?.estimatedBytes ?? -1 >= fixture.libraryFileSize)
  }

  @Test
  func xcodeScannerFindsDerivedDataAndArchives() throws {
    let fixture = try XcodeArtifactFixture()
    defer { fixture.cleanup() }

    let report = CleanupEngine(scanners: [XcodeCleanupScanner()]).scanReport(
      options: CleanupScanOptions(
        roots: [fixture.rootURL.path],
        minimumConfidence: 6,
        maxDepth: 6,
        followSymlinks: false
      )
    )

    #expect(report.summary.total == 2)
    #expect(report.categorySummary[CleanupCategory.xcodeArtifacts.rawValue] == 2)
    #expect(report.totalEstimatedBytes >= fixture.minimumExpectedBytes)

    let titles = Set(report.items.map(\.title))
    #expect(titles.contains("Xcode DerivedData"))
    #expect(titles.contains("Xcode Archives"))
  }

  @Test
  func xcodeScannerDetectsArtifactWhenRootPointsDirectlyAtDerivedData() throws {
    let fixture = try XcodeArtifactFixture()
    defer { fixture.cleanup() }

    let findings = XcodeCleanupScanner().scan(
      options: CleanupScanOptions(
        roots: [fixture.derivedDataURL.path],
        minimumConfidence: 6,
        maxDepth: 2,
        followSymlinks: false
      )
    )

    #expect(findings.count == 1)
    #expect(findings.first?.title == "Xcode DerivedData")
    #expect(findings.first?.estimatedBytes ?? 0 >= fixture.derivedDataMinimumBytes)
  }
}

private struct UnityProjectFixture {
  let rootURL: URL
  let projectURL: URL
  let resolvedProjectPath: String
  let libraryFileSize: Int64

  init(projectName: String, hidden: Bool) throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let projectURL = rootURL.appendingPathComponent(projectName, isDirectory: true)
    let projectSettingsURL = projectURL.appendingPathComponent("ProjectSettings", isDirectory: true)
    let assetsURL = projectURL.appendingPathComponent("Assets", isDirectory: true)
    let libraryURL = projectURL.appendingPathComponent("Library", isDirectory: true)

    try FileManager.default.createDirectory(at: projectSettingsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
    try "m_EditorVersion: 2022.3.1f1\n".write(
      to: projectSettingsURL.appendingPathComponent("ProjectVersion.txt"),
      atomically: true,
      encoding: .utf8
    )

    // Create a dummy file in Library to ensure non-zero reclaimable bytes.
    let libraryFileData = Data(repeating: 0x41, count: 512)
    try libraryFileData.write(to: libraryURL.appendingPathComponent("ArtifactDB"))
    self.libraryFileSize = Int64(libraryFileData.count)

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

private struct XcodeArtifactFixture {
  let rootURL: URL
  let derivedDataURL: URL
  let minimumExpectedBytes: Int64
  let derivedDataMinimumBytes: Int64

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    derivedDataURL = rootURL
      .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
    let archivesURL = rootURL
      .appendingPathComponent("Library/Developer/Xcode/Archives/2026-03-24/App.xcarchive", isDirectory: true)

    let derivedDataFile = derivedDataURL
      .appendingPathComponent("ProjectA/Build/Intermediates.noindex/cache.bin")
    let archiveFile = archivesURL
      .appendingPathComponent("Products/Applications/Demo.app/Demo")

    try FileManager.default.createDirectory(at: derivedDataFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: archiveFile.deletingLastPathComponent(), withIntermediateDirectories: true)

    let derivedDataBytes = Data(repeating: 0x61, count: 2048)
    let archiveBytes = Data(repeating: 0x62, count: 4096)

    try derivedDataBytes.write(to: derivedDataFile)
    try archiveBytes.write(to: archiveFile)

    self.minimumExpectedBytes = Int64(derivedDataBytes.count + archiveBytes.count)
    self.derivedDataMinimumBytes = Int64(derivedDataBytes.count)
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}
