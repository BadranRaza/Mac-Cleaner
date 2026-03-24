import Foundation

public enum CleanupCategory: String, Codable, CaseIterable {
  case unityProjects = "unity-projects"
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
  public let confidenceBand: CleanupConfidenceBand
  public let detectedBy: [String]
  public let detectedAt: Date
  public let cleanupTargets: [CleanupTargetDescriptor]
  public let recommendedAction: String
  public let safetyLevel: CleanupSafetyLevel

  public init(
    id: String,
    title: String,
    subtitle: String,
    metadata: String?,
    path: String,
    category: CleanupCategory,
    sourceScanner: String,
    confidenceScore: Int,
    confidenceBand: CleanupConfidenceBand,
    detectedBy: [String],
    detectedAt: Date,
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
    self.confidenceBand = confidenceBand
    self.detectedBy = detectedBy
    self.detectedAt = detectedAt
    self.cleanupTargets = cleanupTargets
    self.recommendedAction = recommendedAction
    self.safetyLevel = safetyLevel
  }
}

public struct CleanupScanOptions {
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

  public static let `default` = CleanupScanOptions()
}

public struct CleanupScanReport: Codable, Equatable {
  public let scanId: String
  public let scannedAt: Date
  public let scannedRoots: [String]
  public let minimumConfidence: Int
  public let maxDepth: Int?
  public let elapsedMs: Int
  public let scannerCount: Int
  public let items: [CleanupFinding]
  public let summary: [String: Int]
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

    var categories: [String: Int] = [:]
    for item in items {
      categories[item.category.rawValue, default: 0] += 1
    }
    self.categorySummary = categories
    self.summary = [
      "high": items.filter { $0.confidenceBand == .high }.count,
      "medium": items.filter { $0.confidenceBand == .medium }.count,
      "low": items.filter { $0.confidenceBand == .low }.count,
      "total": items.count
    ]
  }
}

public protocol CleanupScanner {
  var id: String { get }
  var displayName: String { get }

  func scan(options: CleanupScanOptions) -> [CleanupFinding]
}

public struct CleanupEngine {
  private let scanners: [any CleanupScanner]

  public init(scanners: [any CleanupScanner] = [UnityCleanupScanner()]) {
    self.scanners = scanners
  }

  public func scan(options: CleanupScanOptions = .default) -> [CleanupFinding] {
    scanners
      .flatMap { $0.scan(options: options) }
      .sorted {
        if $0.confidenceScore == $1.confidenceScore {
          return $0.path < $1.path
        }
        return $0.confidenceScore > $1.confidenceScore
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
      skipHiddenDirectories: options.skipHiddenDirectories,
      followSymlinks: options.followSymlinks
    )

    return detector.scan(options: detectorOptions).map { candidate in
      let pathURL = URL(fileURLWithPath: candidate.path)
      let projectName = pathURL.lastPathComponent.isEmpty ? candidate.path : pathURL.lastPathComponent
      let version = candidate.unityVersion ?? "unknown"

      return CleanupFinding(
        id: candidate.path,
        title: projectName,
        subtitle: "Unity project",
        metadata: "Unity \(version) • \(candidate.detectedBy.count) marker(s)",
        path: candidate.path,
        category: .unityProjects,
        sourceScanner: displayName,
        confidenceScore: candidate.confidence,
        confidenceBand: CleanupConfidenceBand.fromScore(candidate.confidence),
        detectedBy: candidate.detectedBy,
        detectedAt: candidate.detectedAt,
        cleanupTargets: candidate.safeCleanTargets.map {
          CleanupTargetDescriptor(name: $0, relativePath: $0)
        },
        recommendedAction: candidate.recommendedCleanupAction,
        safetyLevel: candidate.confidence >= 10 ? .safeWithConfirmation : .reviewRecommended
      )
    }
  }
}
