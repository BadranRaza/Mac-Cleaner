import Foundation
import MacCleanerCore

let arguments = CommandLine.arguments.dropFirst()
let printJSON = arguments.contains("--json")
let apiMode = arguments.contains("--api")
let followSymlinks = arguments.contains("--follow-symlinks")

let roots: [String] = arguments.compactMap { arg in
  if arg == "--json" || arg == "--api" || arg == "--follow-symlinks" || arg.hasPrefix("--max-depth=") || arg.hasPrefix("--minimum-confidence=") {
    return nil
  }

  if arg.hasPrefix("--root=") {
    return String(arg.dropFirst("--root=".count))
  }

  return nil
}

let maxDepthArg = arguments.first(where: { $0.hasPrefix("--max-depth=") })
let maxDepth = maxDepthArg.flatMap { arg in
  let value = String(arg.dropFirst("--max-depth=".count))
  return Int(value)
}

let minimumConfidenceArg = arguments.first(where: { $0.hasPrefix("--minimum-confidence=") })
let minimumConfidence = minimumConfidenceArg.flatMap { arg in
  let value = String(arg.dropFirst("--minimum-confidence=".count))
  return Int(value)
}

let options = UnityProjectDetectorOptions(
  roots: roots.isEmpty ? [FileManager.default.currentDirectoryPath] : roots,
  minimumConfidence: minimumConfidence ?? 6,
  maxDepth: maxDepth,
  followSymlinks: followSymlinks
)

let detector = UnityProjectDetector()

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

if apiMode {
  let report = detector.scanReport(options: options)
  printJSONPayload(report, context: "API payload")
  exit(0)
}

if printJSON {
  let results = detector.scan(options: options)
  printJSONPayload(results, context: "scan output")
  exit(0)
}

let results = detector.scan(options: options)
if results.isEmpty {
  print("No Unity projects detected.")
  exit(0)
}

print("Detected \(results.count) Unity project(s):")
for item in results {
  let version = item.unityVersion ?? "unknown"
  print("- \(item.path)")
  print("  confidence: \(item.confidence) (\(item.confidenceBand.rawValue))")
  print("  version: \(version)")
  print("  markers: \(item.detectedBy.joined(separator: ", "))")
  print("  action: \(item.recommendedCleanupAction)")
}
