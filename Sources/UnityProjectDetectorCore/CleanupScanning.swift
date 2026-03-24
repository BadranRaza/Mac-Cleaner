import Foundation

public enum CleanupCategory: String, Codable, CaseIterable {
  case unityProjects = "unity-projects"
  case xcodeArtifacts = "xcode-artifacts"
}

public enum CleanupSafetyLevel: String, Codable {
  case safeWithConfirmation = "safe-with-confirmation"
  case reviewRecommended = "review-recommended"
}

public enum CleanupConfidenceBand: String, Codable {
  case low
  case medium
  case high

  public static func fromScore(_ score: Int) -> CleanupConfidenceBand {
    switch score {
    case 0..<7:
      return .low
    case 7...9:
      return .medium
    default:
      return .high
    }
  }
}

public struct CleanupTargetDescriptor: Codable, Equatable, Hashable {
  public let name: String
  public let relativePath: String

  public init(name: String, relativePath: String) {
    self.name = name
    self.relativePath = relativePath
  }
}

public struct CleanupFinding: Codable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let metadata: String?
  public let path: String
  public let category: CleanupCategory
  public let sourceScanner: String
  public let confidenceScore: Int
  public let detectedBy: [String]
  public let detectedAt: Date
  public let estimatedBytes: Int64
  public let cleanupTargets: [CleanupTargetDescriptor]
  public let recommendedAction: String
  public let safetyLevel: CleanupSafetyLevel

  /// Derived from `confidenceScore` — always consistent, never out of sync.
  public var confidenceBand: CleanupConfidenceBand {
    CleanupConfidenceBand.fromScore(confidenceScore)
  }

  public init(
    id: String,
    title: String,
    subtitle: String,
    metadata: String?,
    path: String,
    category: CleanupCategory,
    sourceScanner: String,
    confidenceScore: Int,
    detectedBy: [String],
    detectedAt: Date,
    estimatedBytes: Int64,
    cleanupTargets: [CleanupTargetDescriptor],
    recommendedAction: String,
    safetyLevel: CleanupSafetyLevel
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.metadata = metadata
    self.path = path
    self.category = category
    self.sourceScanner = sourceScanner
    self.confidenceScore = confidenceScore
    self.detectedBy = detectedBy
    self.detectedAt = detectedAt
    self.estimatedBytes = estimatedBytes
    self.cleanupTargets = cleanupTargets
    self.recommendedAction = recommendedAction
    self.safetyLevel = safetyLevel
  }

  // Custom Codable to encode derived confidenceBand for JSON consumers.
  private enum CodingKeys: String, CodingKey {
    case id, title, subtitle, metadata, path, category, sourceScanner
    case confidenceScore, confidenceBand, detectedBy, detectedAt
    case estimatedBytes, cleanupTargets, recommendedAction, safetyLevel
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(subtitle, forKey: .subtitle)
    try container.encodeIfPresent(metadata, forKey: .metadata)
    try container.encode(path, forKey: .path)
    try container.encode(category, forKey: .category)
    try container.encode(sourceScanner, forKey: .sourceScanner)
    try container.encode(confidenceScore, forKey: .confidenceScore)
    try container.encode(confidenceBand, forKey: .confidenceBand)
    try container.encode(detectedBy, forKey: .detectedBy)
    try container.encode(detectedAt, forKey: .detectedAt)
    try container.encode(estimatedBytes, forKey: .estimatedBytes)
    try container.encode(cleanupTargets, forKey: .cleanupTargets)
    try container.encode(recommendedAction, forKey: .recommendedAction)
    try container.encode(safetyLevel, forKey: .safetyLevel)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    subtitle = try container.decode(String.self, forKey: .subtitle)
    metadata = try container.decodeIfPresent(String.self, forKey: .metadata)
    path = try container.decode(String.self, forKey: .path)
    category = try container.decode(CleanupCategory.self, forKey: .category)
    sourceScanner = try container.decode(String.self, forKey: .sourceScanner)
    confidenceScore = try container.decode(Int.self, forKey: .confidenceScore)
    // confidenceBand is derived — decode and discard (or ignore if absent)
    detectedBy = try container.decode([String].self, forKey: .detectedBy)
    detectedAt = try container.decode(Date.self, forKey: .detectedAt)
    estimatedBytes = try container.decode(Int64.self, forKey: .estimatedBytes)
    cleanupTargets = try container.decode([CleanupTargetDescriptor].self, forKey: .cleanupTargets)
    recommendedAction = try container.decode(String.self, forKey: .recommendedAction)
    safetyLevel = try container.decode(CleanupSafetyLevel.self, forKey: .safetyLevel)
  }
}

public struct CleanupScanOptions: Codable {
  public let roots: [String]
  public let minimumConfidence: Int
  public let maxDepth: Int?
  public let followSymlinks: Bool

  public init(
    roots: [String] = [],
    minimumConfidence: Int = 6,
    maxDepth: Int? = nil,
    followSymlinks: Bool = false
  ) {
    self.roots = roots
    self.minimumConfidence = minimumConfidence
    self.maxDepth = maxDepth
    self.followSymlinks = followSymlinks
  }

  public static let `default` = CleanupScanOptions()
}

public struct ConfidenceSummary: Codable, Equatable {
  public let high: Int
  public let medium: Int
  public let low: Int
  public let total: Int

  public init(high: Int, medium: Int, low: Int, total: Int) {
    self.high = high
    self.medium = medium
    self.low = low
    self.total = total
  }

  public init(items: [CleanupFinding]) {
    self.high = items.filter { $0.confidenceBand == .high }.count
    self.medium = items.filter { $0.confidenceBand == .medium }.count
    self.low = items.filter { $0.confidenceBand == .low }.count
    self.total = items.count
  }
}

public struct CleanupScanReport: Codable, Equatable {
  public let scanId: String
  public let scannedAt: Date
  public let scannedRoots: [String]
  public let minimumConfidence: Int
  public let maxDepth: Int?
  public let elapsedMs: Int
  public let scannerCount: Int
  public let totalEstimatedBytes: Int64
  public let items: [CleanupFinding]
  public let summary: ConfidenceSummary
  public let categorySummary: [String: Int]

  public init(
    scanId: String,
    scannedAt: Date,
    scannedRoots: [String],
    minimumConfidence: Int,
    maxDepth: Int?,
    elapsedMs: Int,
    scannerCount: Int,
    items: [CleanupFinding]
  ) {
    self.scanId = scanId
    self.scannedAt = scannedAt
    self.scannedRoots = scannedRoots
    self.minimumConfidence = minimumConfidence
    self.maxDepth = maxDepth
    self.elapsedMs = elapsedMs
    self.scannerCount = scannerCount
    self.items = items
    self.totalEstimatedBytes = items.reduce(into: 0) { partialResult, item in
      partialResult += item.estimatedBytes
    }

    var categories: [String: Int] = [:]
    for item in items {
      categories[item.category.rawValue, default: 0] += 1
    }
    self.categorySummary = categories
    self.summary = ConfidenceSummary(items: items)
  }
}

public protocol CleanupScanner {
  var id: String { get }
  var displayName: String { get }

  func scan(options: CleanupScanOptions) -> [CleanupFinding]
}

public struct CleanupEngine {
  private let scanners: [any CleanupScanner]

  public init(scanners: [any CleanupScanner] = [UnityCleanupScanner(), XcodeCleanupScanner()]) {
    self.scanners = scanners
  }

  public func scan(options: CleanupScanOptions = .default) -> [CleanupFinding] {
    scanners
      .flatMap { $0.scan(options: options) }
      .sorted {
        if $0.estimatedBytes == $1.estimatedBytes {
          if $0.confidenceScore == $1.confidenceScore {
            return $0.path < $1.path
          }
          return $0.confidenceScore > $1.confidenceScore
        }
        return $0.estimatedBytes > $1.estimatedBytes
      }
  }

  public func scanReport(options: CleanupScanOptions = .default) -> CleanupScanReport {
    let scanStart = Date()
    let items = scan(options: options)
    let elapsedMs = Int(Date().timeIntervalSince(scanStart) * 1000)

    return CleanupScanReport(
      scanId: UUID().uuidString,
      scannedAt: scanStart,
      scannedRoots: options.roots,
      minimumConfidence: options.minimumConfidence,
      maxDepth: options.maxDepth,
      elapsedMs: elapsedMs,
      scannerCount: scanners.count,
      items: items
    )
  }
}

public struct UnityCleanupScanner: CleanupScanner {
  public let id = "unity"
  public let displayName = "Unity"

  private let detector: UnityProjectDetector

  public init(detector: UnityProjectDetector = UnityProjectDetector()) {
    self.detector = detector
  }

  public func scan(options: CleanupScanOptions) -> [CleanupFinding] {
    let detectorOptions = UnityProjectDetectorOptions(
      roots: options.roots,
      minimumConfidence: options.minimumConfidence,
      maxDepth: options.maxDepth,
      followSymlinks: options.followSymlinks
    )

    return detector.scan(options: detectorOptions).compactMap { candidate in
      let pathURL = URL(fileURLWithPath: candidate.path)
      let projectName = pathURL.lastPathComponent.isEmpty ? candidate.path : pathURL.lastPathComponent
      let version = candidate.unityVersion ?? "unknown"

      // Only include cleanup targets that actually exist on disk.
      let cleanupTargets = candidate.safeCleanTargets.compactMap { targetName -> CleanupTargetDescriptor? in
        let targetURL = pathURL.appendingPathComponent(targetName, isDirectory: true)
        guard CleanupSizing.directoryExists(at: targetURL) else {
          return nil
        }
        return CleanupTargetDescriptor(name: targetName, relativePath: targetName)
      }

      // Skip findings with no reclaimable targets.
      guard !cleanupTargets.isEmpty else {
        return nil
      }

      let estimatedBytes = cleanupTargets.reduce(into: Int64(0)) { partialResult, target in
        let targetURL = pathURL.appendingPathComponent(target.relativePath, isDirectory: true)
        partialResult += CleanupSizing.directorySize(at: targetURL)
      }
      let sizeSummary = CleanupSizing.byteCountString(for: estimatedBytes)

      return CleanupFinding(
        id: "\(id):\(candidate.path)",
        title: projectName,
        subtitle: "Unity project",
        metadata: "Unity \(version) • \(candidate.detectedBy.count) marker(s) • \(sizeSummary) reclaimable",
        path: candidate.path,
        category: .unityProjects,
        sourceScanner: displayName,
        confidenceScore: candidate.confidence,
        detectedBy: candidate.detectedBy,
        detectedAt: candidate.detectedAt,
        estimatedBytes: estimatedBytes,
        cleanupTargets: cleanupTargets,
        recommendedAction: candidate.recommendedCleanupAction,
        safetyLevel: candidate.confidence >= 10 ? .safeWithConfirmation : .reviewRecommended
      )
    }
  }
}

public struct XcodeCleanupScanner: CleanupScanner {
  public let id = "xcode"
  public let displayName = "Xcode"

  private let fileManager = FileManager.default

  public init() {}

  public func scan(options: CleanupScanOptions) -> [CleanupFinding] {
    guard !options.roots.isEmpty else {
      return []
    }

    var findings: [CleanupFinding] = []
    var seenPaths = Set<String>()

    for rootPath in options.roots {
      let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
      scanDirectory(
        rootURL,
        currentDepth: 0,
        options: options,
        findings: &findings,
        seenPaths: &seenPaths
      )
    }

    return findings
  }

  private func scanDirectory(
    _ directoryURL: URL,
    currentDepth: Int,
    options: CleanupScanOptions,
    findings: inout [CleanupFinding],
    seenPaths: inout Set<String>
  ) {
    if let finding = makeFindingIfArtifact(directoryURL, options: options),
       seenPaths.insert(finding.path).inserted {
      findings.append(finding)
    }

    if let maxDepth = options.maxDepth, currentDepth >= maxDepth {
      return
    }

    guard let children = try? fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
      options: []
    ) else {
      return
    }

    for child in children {
      let name = child.lastPathComponent
      if name.hasPrefix(".") {
        continue
      }

      guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
            values.isDirectory == true else {
        continue
      }

      if options.followSymlinks == false && values.isSymbolicLink == true {
        continue
      }

      if values.isPackage == true {
        continue
      }

      scanDirectory(
        child.standardizedFileURL,
        currentDepth: currentDepth + 1,
        options: options,
        findings: &findings,
        seenPaths: &seenPaths
      )
    }
  }

  private func makeFindingIfArtifact(_ directoryURL: URL, options: CleanupScanOptions) -> CleanupFinding? {
    let path = directoryURL.standardizedFileURL.path
    let pathComponents = directoryURL.pathComponents
    let name = directoryURL.lastPathComponent

    let isDerivedData = name == "DerivedData" && pathComponents.contains("Xcode")
    let isArchives = name == "Archives" && pathComponents.contains("Xcode")
    guard isDerivedData || isArchives else {
      return nil
    }

    let estimatedBytes = CleanupSizing.directorySize(at: directoryURL)
    let itemCount = CleanupSizing.immediateChildCount(at: directoryURL)
    let sizeSummary = CleanupSizing.byteCountString(for: estimatedBytes)

    if isDerivedData {
      return CleanupFinding(
        id: "\(id):\(path)",
        title: "Xcode DerivedData",
        subtitle: "Build cache",
        metadata: "\(itemCount) item(s) • \(sizeSummary) reclaimable",
        path: path,
        category: .xcodeArtifacts,
        sourceScanner: displayName,
        confidenceScore: 10,
        detectedBy: ["Xcode/DerivedData"],
        detectedAt: Date(),
        estimatedBytes: estimatedBytes,
        cleanupTargets: [CleanupTargetDescriptor(name: "All contents", relativePath: ".")],
        recommendedAction: "Safe to remove DerivedData contents. Xcode rebuilds these caches automatically.",
        safetyLevel: .safeWithConfirmation
      )
    }

    return CleanupFinding(
      id: "\(id):\(path)",
      title: "Xcode Archives",
      subtitle: "Archived builds",
      metadata: "\(itemCount) item(s) • \(sizeSummary) reclaimable",
      path: path,
      category: .xcodeArtifacts,
      sourceScanner: displayName,
      confidenceScore: 8,
      detectedBy: ["Xcode/Archives"],
      detectedAt: Date(),
      estimatedBytes: estimatedBytes,
      cleanupTargets: [CleanupTargetDescriptor(name: "All contents", relativePath: ".")],
      recommendedAction: "Review archives before cleanup. Delete only archives you no longer need for distribution, symbolication, or export history.",
      safetyLevel: .reviewRecommended
    )
  }
}
