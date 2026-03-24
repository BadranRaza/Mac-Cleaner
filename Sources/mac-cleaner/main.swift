import Foundation
import MacCleanerCore

let arguments = CommandLine.arguments.dropFirst()
let printJSON = arguments.contains("--json")
let includeHidden = arguments.contains("--include-hidden")
let followSymlinks = arguments.contains("--follow-symlinks")

let roots: [String] = arguments.compactMap { arg in
  if arg == "--json" || arg == "--include-hidden" || arg == "--follow-symlinks" || arg.hasPrefix("--max-depth=") || arg.hasPrefix("--minimum-confidence=") {
    return nil
  }

  if arg.hasPrefix("--root=") {
    return String(arg.dropFirst("--root=".count))
  }

  return nil
}

let maxDepthArg = arguments.first(where: { $0.hasPrefix("--max-depth=") })
let maxDepth = maxDepthArg.flatMap { arg in
  Int(String(arg.dropFirst("--max-depth=".count)))
}

let minimumConfidenceArg = arguments.first(where: { $0.hasPrefix("--minimum-confidence=") })
let minimumConfidence = minimumConfidenceArg.flatMap { arg in
  Int(String(arg.dropFirst("--minimum-confidence=".count)))
}

let options = CleanupScanOptions(
  roots: roots.isEmpty ? [FileManager.default.currentDirectoryPath] : roots,
  minimumConfidence: minimumConfidence ?? 6,
  maxDepth: maxDepth,
  skipHiddenDirectories: !includeHidden,
  followSymlinks: followSymlinks
)

let engine = CleanupEngine()

func printJSONPayload<T: Encodable>(_ value: T, context: String) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  encoder.dateEncodingStrategy = .iso8601

  do {
    let payload = try encoder.encode(value)
    FileHandle.standardOutput.write(payload)
  } catch {
    print("Failed to encode \(context): \(error.localizedDescription)")
    exit(1)
  }
}

let report = engine.scanReport(options: options)

if printJSON {
  printJSONPayload(report, context: "scan report")
  exit(0)
}

let total = report.summary["total", default: 0]
if total == 0 {
  print("No cleanup findings detected.")
  exit(0)
}

print("Detected \(total) cleanup finding(s):")
for item in report.items {
  let cleanupTargets = item.cleanupTargets.map(\.name).joined(separator: ", ")
  print("- \(item.title) [\(item.subtitle)]")
  print("  path: \(item.path)")
  print("  scanner: \(item.sourceScanner)")
  print("  confidence: \(item.confidenceScore) (\(item.confidenceBand.rawValue))")
  if let metadata = item.metadata {
    print("  details: \(metadata)")
  }
  print("  cleanup targets: \(cleanupTargets)")
  print("  action: \(item.recommendedAction)")
}
