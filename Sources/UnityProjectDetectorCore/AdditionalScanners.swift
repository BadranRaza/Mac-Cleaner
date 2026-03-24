import Foundation

public struct TrashCleanupScanner: CleanupScanner {
  public let id = "trash"
  public let displayName = "Trash Bin"

  private let fileManager = FileManager.default

  public init() {}

  public func scan(options: CleanupScanOptions) -> [CleanupFinding] {
    guard !options.roots.isEmpty else { return [] }

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
    if let finding = makeFindingIfTrash(directoryURL), seenPaths.insert(finding.path).inserted {
      findings.append(finding)
    }

    if let maxDepth = options.maxDepth, currentDepth >= maxDepth { return }

    guard let children = try? fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
      options: []
    ) else { return }

    for child in children {
      let name = child.lastPathComponent
      // We only want to descend into normal directories, but we must explicitly allow ".Trash"
      if name.hasPrefix(".") && name != ".Trash" {
        continue
      }

      guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
            values.isDirectory == true else {
        continue
      }

      if values.isSymbolicLink == true || values.isPackage == true {
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

  private func makeFindingIfTrash(_ directoryURL: URL) -> CleanupFinding? {
    let name = directoryURL.lastPathComponent
    guard name == ".Trash" || name == ".Trashes" else { return nil }

    let estimatedBytes = CleanupSizing.directorySize(at: directoryURL)
    let itemCount = CleanupSizing.immediateChildCount(at: directoryURL)
    
    // Don't report empty trash
    guard itemCount > 0 else { return nil }

    let sizeSummary = CleanupSizing.byteCountString(for: estimatedBytes)

    return CleanupFinding(
      id: "\(id):\(directoryURL.path)",
      title: "Trash Bin",
      subtitle: "Deleted files",
      metadata: "\(itemCount) item(s) • \(sizeSummary) reclaimable",
      path: directoryURL.path,
      category: .trash,
      sourceScanner: displayName,
      confidenceScore: 10,
      detectedBy: ["Trash folder"],
      detectedAt: Date(),
      estimatedBytes: estimatedBytes,
      cleanupTargets: [CleanupTargetDescriptor(name: "All contents", relativePath: ".")],
      recommendedAction: "Safe to empty trash. Files are permanently deleted.",
      safetyLevel: .safeWithConfirmation
    )
  }
}

public struct AppCachesScanner: CleanupScanner {
  public let id = "app-caches"
  public let displayName = "App Caches"
  private let fileManager = FileManager.default

  public init() {}

  public func scan(options: CleanupScanOptions) -> [CleanupFinding] {
    guard !options.roots.isEmpty else { return [] }
    var findings: [CleanupFinding] = []
    var seenPaths = Set<String>()

    for rootPath in options.roots {
      let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
      scanDirectory(rootURL, currentDepth: 0, options: options, findings: &findings, seenPaths: &seenPaths)
    }
    return findings
  }

  private func scanDirectory(
    _ directoryURL: URL, currentDepth: Int, options: CleanupScanOptions,
    findings: inout [CleanupFinding], seenPaths: inout Set<String>
  ) {
    if let finding = makeFindingIfCache(directoryURL), seenPaths.insert(finding.path).inserted {
      findings.append(finding)
      // Stop traversing further down inside a cache folder (we just delete the cache folder contents)
      return 
    }

    if let maxDepth = options.maxDepth, currentDepth >= maxDepth { return }

    guard let children = try? fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
      options: []
    ) else { return }

    for child in children {
      let name = child.lastPathComponent
      if name.hasPrefix(".") { continue }

      guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
            values.isDirectory == true, values.isSymbolicLink == false, values.isPackage == false else {
        continue
      }

      scanDirectory(child.standardizedFileURL, currentDepth: currentDepth + 1, options: options, findings: &findings, seenPaths: &seenPaths)
    }
  }

  private func makeFindingIfCache(_ directoryURL: URL) -> CleanupFinding? {
    let pathComponents = directoryURL.pathComponents
    let name = directoryURL.lastPathComponent
    let isLibrary = pathComponents.contains("Library")
    
    let isCaches = name == "Caches" && isLibrary
    let isLogs = name == "Logs" && isLibrary

    guard isCaches || isLogs else { return nil }

    let estimatedBytes = CleanupSizing.directorySize(at: directoryURL)
    let itemCount = CleanupSizing.immediateChildCount(at: directoryURL)
    
    guard itemCount > 0 else { return nil }

    let sizeSummary = CleanupSizing.byteCountString(for: estimatedBytes)
    let label = isCaches ? "Application Caches" : "System Logs"
    
    return CleanupFinding(
      id: "\(id):\(directoryURL.path)",
      title: label,
      subtitle: isCaches ? "Temporary cache files" : "Application & System Logs",
      metadata: "\(itemCount) item(s) • \(sizeSummary) reclaimable",
      path: directoryURL.path,
      category: .applicationCaches,
      sourceScanner: displayName,
      confidenceScore: 8,
      detectedBy: ["Library/\(name)"],
      detectedAt: Date(),
      estimatedBytes: estimatedBytes,
      cleanupTargets: [CleanupTargetDescriptor(name: "All contents", relativePath: ".")],
      recommendedAction: isCaches 
        ? "Safe to remove. Apps will recreate cache files as needed."
        : "Safe to remove. Logs can consume space over time.",
      safetyLevel: .safeWithConfirmation
    )
  }
}

public struct DeveloperCachesScanner: CleanupScanner {
  public let id = "developer-caches"
  public let displayName = "Developer Utilities"
  private let fileManager = FileManager.default

  public init() {}

  public func scan(options: CleanupScanOptions) -> [CleanupFinding] {
    guard !options.roots.isEmpty else { return [] }
    var findings: [CleanupFinding] = []
    var seenPaths = Set<String>()

    for rootPath in options.roots {
      let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
      scanDirectory(rootURL, currentDepth: 0, options: options, findings: &findings, seenPaths: &seenPaths)
    }
    return findings
  }

  private func scanDirectory(
    _ directoryURL: URL, currentDepth: Int, options: CleanupScanOptions,
    findings: inout [CleanupFinding], seenPaths: inout Set<String>
  ) {
    if let finding = makeFindingIfDevArtifact(directoryURL), seenPaths.insert(finding.path).inserted {
      findings.append(finding)
      return
    }

    if let maxDepth = options.maxDepth, currentDepth >= maxDepth { return }

    guard let children = try? fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
      options: []
    ) else { return }

    for child in children {
      let name = child.lastPathComponent
      // allow .gradle and hidden files for node_modules inside hidden temp folders maybe?
      // but to be safe, `.gradle` is explicit
      if name.hasPrefix(".") && name != ".gradle" { continue }

      guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
            values.isDirectory == true, values.isSymbolicLink == false, values.isPackage == false else {
        continue
      }

      scanDirectory(child.standardizedFileURL, currentDepth: currentDepth + 1, options: options, findings: &findings, seenPaths: &seenPaths)
    }
  }

  private func makeFindingIfDevArtifact(_ directoryURL: URL) -> CleanupFinding? {
    let name = directoryURL.lastPathComponent
    let isNodeModules = name == "node_modules"
    let isGradleCaches = name == "caches" && directoryURL.pathComponents.dropLast().last == ".gradle"
    let isCocoaPods = name == "Pods" && (try? fileManager.contentsOfDirectory(atPath: directoryURL.path).contains("Manifest.lock")) == true

    guard isNodeModules || isGradleCaches || isCocoaPods else { return nil }

    let estimatedBytes = CleanupSizing.directorySize(at: directoryURL)
    let itemCount = CleanupSizing.immediateChildCount(at: directoryURL)
    guard estimatedBytes > 0 else { return nil }
    
    let sizeSummary = CleanupSizing.byteCountString(for: estimatedBytes)

    var title = ""
    var subtitle = ""
    if isNodeModules {
      title = "Node Modules"
      subtitle = "Javascript dependencies"
    } else if isGradleCaches {
      title = "Gradle Caches"
      subtitle = "Android build caches"
    } else if isCocoaPods {
      title = "CocoaPods"
      subtitle = "iOS dependencies"
    }

    return CleanupFinding(
      id: "\(id):\(directoryURL.path)",
      title: title,
      subtitle: subtitle,
      metadata: "\(itemCount) item(s) • \(sizeSummary) reclaimable",
      path: directoryURL.path,
      category: .developerCaches,
      sourceScanner: displayName,
      confidenceScore: 9,
      detectedBy: [title],
      detectedAt: Date(),
      estimatedBytes: estimatedBytes,
      cleanupTargets: [CleanupTargetDescriptor(name: "All contents", relativePath: ".")],
      recommendedAction: "Safe to remove. Reinstall dependencies or rebuild the project.",
      safetyLevel: .safeWithConfirmation
    )
  }
}
