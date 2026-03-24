import Foundation

public enum UnityProjectConfidenceBand: String, Codable {
  case low
  case medium
  case high

  public static func fromScore(_ score: Int) -> UnityProjectConfidenceBand {
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

public extension UnityProjectCandidate {
  var confidenceBand: UnityProjectConfidenceBand {
    UnityProjectConfidenceBand.fromScore(confidence)
  }

  var recommendedCleanupAction: String {
    switch confidenceBand {
    case .high:
      return "Safe to clean cache folders and generated build artifacts after user confirmation."
    case .medium:
      return "Run a strict preview and ask user to confirm cache-only cleanup."
    case .low:
      return "Show as low-confidence candidate; require manual review before any cleanup."
    }
  }
}

public struct UnityProjectDetectionItem: Codable, Equatable {
  public let id: String
  public let path: String
  public let confidenceScore: Int
  public let confidenceBand: UnityProjectConfidenceBand
  public let detectedBy: [String]
  public let unityVersion: String?
  public let detectedAt: Date
  public let safeCleanTargets: [String]
  public let recommendedCleanupAction: String

  public init(from candidate: UnityProjectCandidate) {
    self.id = candidate.path
    self.path = candidate.path
    self.confidenceScore = candidate.confidence
    self.confidenceBand = candidate.confidenceBand
    self.detectedBy = candidate.detectedBy
    self.unityVersion = candidate.unityVersion
    self.detectedAt = candidate.detectedAt
    self.safeCleanTargets = candidate.safeCleanTargets
    self.recommendedCleanupAction = candidate.recommendedCleanupAction
  }
}

public struct UnityProjectDetectionReport: Codable, Equatable {
  public let scanId: String
  public let scannedAt: Date
  public let scannedRoots: [String]
  public let minimumConfidence: Int
  public let maxDepth: Int?
  public let elapsedMs: Int
  public let items: [UnityProjectDetectionItem]
  public let summary: [String: Int]

  public init(scanId: String, scannedAt: Date, scannedRoots: [String], minimumConfidence: Int, maxDepth: Int?, elapsedMs: Int, items: [UnityProjectDetectionItem]) {
    self.scanId = scanId
    self.scannedAt = scannedAt
    self.scannedRoots = scannedRoots
    self.minimumConfidence = minimumConfidence
    self.maxDepth = maxDepth
    self.elapsedMs = elapsedMs
    self.items = items
    self.summary = [
      "high": items.filter { $0.confidenceBand == .high }.count,
      "medium": items.filter { $0.confidenceBand == .medium }.count,
      "low": items.filter { $0.confidenceBand == .low }.count,
      "total": items.count
    ]
  }
}

