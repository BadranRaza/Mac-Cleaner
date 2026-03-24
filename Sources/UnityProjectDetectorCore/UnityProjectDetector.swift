import Foundation

public struct UnityProjectCandidate: Codable, Equatable {
  public let path: String
  public let confidence: Int
  public let detectedBy: [String]
  public let unityVersion: String?
  public let detectedAt: Date

  public init(
    path: String,
    confidence: Int,
    detectedBy: [String],
    unityVersion: String?,
    detectedAt: Date = Date()
  ) {
    self.path = path
    self.confidence = confidence
    self.detectedBy = detectedBy
    self.unityVersion = unityVersion
    self.detectedAt = detectedAt
  }

  public var safeCleanTargets: [String] {
    ["Library", "Temp", "Obj", "Logs", "UserSettings"]
  }

  public var isHighConfidence: Bool {
    confidence >= 10
  }
}

public struct UnityProjectDetectorOptions {
  public let roots: [String]
  public let minimumConfidence: Int
  public let maxDepth: Int?
  public let skipHiddenDirectories: Bool
  public let followSymlinks: Bool

  public init(
    roots: [String] = [],
    minimumConfidence: Int = 6,
    maxDepth: Int? = nil,
    skipHiddenDirectories: Bool = true,
    followSymlinks: Bool = false
  ) {
    self.roots = roots
    self.minimumConfidence = minimumConfidence
    self.maxDepth = maxDepth
    self.skipHiddenDirectories = skipHiddenDirectories
    self.followSymlinks = followSymlinks
  }

  public static let `default` = UnityProjectDetectorOptions()
}

public final class UnityProjectDetector {
  private let fileManager = FileManager.default
  private let skipSystemPaths: Set<String> = [
    "/System",
    "/private",
    "/usr",
    "/dev",
    "/Volumes/Microsoft",
    "/Volumes/Recovery",
    "/Library/Caches",
    "/Library/Logs"
  ]
  private let skipDirectoryNames: Set<String> = [
    ".fseventsd",
    ".Spotlight-V100",
    ".DocumentRevisions-V100",
    ".TemporaryItems",
    ".Trash"
  ]
  private let skipPackageExtensions: Set<String> = [
    "app",
    "framework",
    "kext",
    "plugin",
    "bundle",
    "xpc"
  ]

  public init() {}

  public func scan(options: UnityProjectDetectorOptions = .default) -> [UnityProjectCandidate] {
    guard options.roots.isEmpty == false else {
      return []
    }

    var candidates: [UnityProjectCandidate] = []
    let rootURLs = options.roots.map { URL(fileURLWithPath: $0, isDirectory: true) }
    var visited: Set<String> = []

    for root in rootURLs {
      if let candidate = detectUnityProject(at: root, minimumConfidence: options.minimumConfidence) {
        if !candidates.contains(where: { $0.path == candidate.path }) {
          candidates.append(candidate)
        }
      }

      walkDirectory(
        at: root,
        depth: 0,
        options: options,
        candidates: &candidates,
        visited: &visited
      )
    }

    return candidates.sorted {
      if $0.confidence == $1.confidence {
        return $0.path < $1.path
      }
      return $0.confidence > $1.confidence
    }
  }

  public func scanReport(options: UnityProjectDetectorOptions = .default) -> UnityProjectDetectionReport {
    let scanStart = Date()
    let candidates = scan(options: options)
    let items = candidates.map(UnityProjectDetectionItem.init)
    let elapsedMs = Int(Date().timeIntervalSince(scanStart) * 1000)

    return UnityProjectDetectionReport(
      scanId: UUID().uuidString,
      scannedAt: scanStart,
      scannedRoots: options.roots,
      minimumConfidence: options.minimumConfidence,
      maxDepth: options.maxDepth,
      elapsedMs: elapsedMs,
      items: items
    )
  }

  private func walkDirectory(
    at directory: URL,
    depth: Int,
    options: UnityProjectDetectorOptions,
    candidates: inout [UnityProjectCandidate],
    visited: inout Set<String>
  ) {
    let directoryPath = directory.standardized.path

    if visited.contains(directoryPath) {
      return
    }
    visited.insert(directoryPath)

    if shouldSkip(directory, options: options) {
      return
    }

    if let maxDepth = options.maxDepth, depth > maxDepth {
      return
    }

    guard let childItems = try? fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
      options: options.skipHiddenDirectories ? [.skipsHiddenFiles] : []
    ) else {
      return
    }

    for item in childItems {
      let name = item.lastPathComponent

      if options.skipHiddenDirectories && shouldSkipName(name) {
        continue
      }

      guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
            values.isDirectory == true else {
        continue
      }

      if options.followSymlinks == false && (values.isSymbolicLink == true) {
        continue
      }

      if skipBundledApplication(item) {
        continue
      }

      if values.isPackage == true {
        continue
      }

      if let candidate = detectUnityProject(at: item, minimumConfidence: options.minimumConfidence) {
        if !candidates.contains(where: { $0.path == candidate.path }) {
          candidates.append(candidate)
        }
      }

      if let maxDepth = options.maxDepth, depth >= maxDepth {
        continue
      }

      walkDirectory(
        at: item,
        depth: depth + 1,
        options: options,
        candidates: &candidates,
        visited: &visited
      )
    }
  }

  private func detectUnityProject(
    at projectRoot: URL,
    minimumConfidence: Int
  ) -> UnityProjectCandidate? {
    let projectSettingsPath = projectRoot.appendingPathComponent("ProjectSettings")
    let assetsPath = projectRoot.appendingPathComponent("Assets")
    let packagesPath = projectRoot.appendingPathComponent("Packages")
    let versionFile = projectSettingsPath.appendingPathComponent("ProjectVersion.txt")
    let projectSettingsAsset = projectSettingsPath.appendingPathComponent("ProjectSettings.asset")
    let manifestFile = packagesPath.appendingPathComponent("manifest.json")
    let userSettingsPath = projectRoot.appendingPathComponent("UserSettings")

    let hasProjectSettings = isDirectory(projectSettingsPath)
    let hasAssets = isDirectory(assetsPath)
    let hasPackages = isDirectory(packagesPath)
    let hasVersionFile = fileExists(versionFile)
    let hasManifest = fileExists(manifestFile)
    let hasProjectSettingsAsset = fileExists(projectSettingsAsset)
    let hasUserSettings = isDirectory(userSettingsPath)
    let unityVersion = hasVersionFile ? parseUnityVersion(from: versionFile) : nil

    let requiredSignal = hasProjectSettings && (hasAssets || hasPackages)
    guard requiredSignal else {
      return nil
    }

    var confidence = 0
    var reasons: [String] = []

    if hasVersionFile {
      confidence += 5
      reasons.append("ProjectSettings/ProjectVersion.txt")
    }
    if hasProjectSettings {
      confidence += 2
      reasons.append("ProjectSettings/")
    }
    if hasAssets {
      confidence += 2
      reasons.append("Assets/")
    }
    if hasPackages {
      confidence += 2
      reasons.append("Packages/")
    }
    if hasManifest {
      confidence += 1
      reasons.append("Packages/manifest.json")
    }
    if hasProjectSettingsAsset {
      confidence += 1
      reasons.append("ProjectSettings/ProjectSettings.asset")
    }
    if hasUserSettings {
      confidence += 1
      reasons.append("UserSettings/")
    }

    guard confidence >= minimumConfidence else {
      return nil
    }

    return UnityProjectCandidate(
      path: projectRoot.standardized.path,
      confidence: confidence,
      detectedBy: reasons,
      unityVersion: unityVersion
    )
  }

  private func parseUnityVersion(from fileURL: URL) -> String? {
    guard let fileContents = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return nil
    }

    for line in fileContents.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("m_EditorVersion:") {
        let value = trimmed
          .replacingOccurrences(of: "m_EditorVersion:", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
      }
    }

    return nil
  }

  private func shouldSkip(_ url: URL, options: UnityProjectDetectorOptions) -> Bool {
    let path = url.path

    if options.skipHiddenDirectories && isHiddenPath(path) {
      return true
    }

    if skipSystemPaths.contains(where: { systemPath in
      path == systemPath || path.hasPrefix(systemPath + "/")
    }) {
      return true
    }

    return false
  }

  private func isHiddenPath(_ path: String) -> Bool {
    let components = path.split(separator: "/")
    return components.contains(where: { $0.hasPrefix(".") })
  }

  private func shouldSkipName(_ name: String) -> Bool {
    return skipDirectoryNames.contains(name)
  }

  private func skipBundledApplication(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext.isEmpty == false && skipPackageExtensions.contains(ext)
  }

  private func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return false
    }
    return isDirectory.boolValue
  }

  private func fileExists(_ url: URL) -> Bool {
    return fileManager.fileExists(atPath: url.path)
  }
}
