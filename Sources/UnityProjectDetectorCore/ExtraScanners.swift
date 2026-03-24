import Foundation

public struct MailAttachmentsScanner: CleanupScanner {
  public let id = "mail-attachments"
  public let displayName = "Mail Attachments"
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
    if let finding = makeFindingIfMailDownloads(directoryURL), seenPaths.insert(finding.path).inserted {
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
      if name.hasPrefix(".") { continue }
      guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
            values.isDirectory == true, values.isSymbolicLink == false, values.isPackage == false else {
        continue
      }
      scanDirectory(child.standardizedFileURL, currentDepth: currentDepth + 1, options: options, findings: &findings, seenPaths: &seenPaths)
    }
  }

  private func makeFindingIfMailDownloads(_ directoryURL: URL) -> CleanupFinding? {
    let name = directoryURL.lastPathComponent
    let pathComponents = directoryURL.pathComponents
    
    // Strict match: Must be named "Mail Downloads" and reside in the expected Mail container hierarchy.
    let isMailDownloads = name == "Mail Downloads" && pathComponents.contains("com.apple.mail")
    guard isMailDownloads else { return nil }

    let estimatedBytes = CleanupSizing.directorySize(at: directoryURL)
    let itemCount = CleanupSizing.immediateChildCount(at: directoryURL)
    guard estimatedBytes > 0 else { return nil }

    let sizeSummary = CleanupSizing.byteCountString(for: estimatedBytes)

    return CleanupFinding(
      id: "\(id):\(directoryURL.path)",
      title: "Apple Mail Attachments",
      subtitle: "Cached email attachments",
      metadata: "\(itemCount) item(s) • \(sizeSummary) reclaimable",
      path: directoryURL.path,
      category: .mailAttachments,
      sourceScanner: displayName,
      confidenceScore: 10,
      detectedBy: ["Mail Downloads"],
      detectedAt: Date(),
      estimatedBytes: estimatedBytes,
      cleanupTargets: [CleanupTargetDescriptor(name: "All contents", relativePath: ".")],
      recommendedAction: "Safe to delete. Apple Mail will redownload the attachment from the server if you try to open the email again.",
      safetyLevel: .safeWithConfirmation
    )
  }
}

public struct PackageManagerScanner: CleanupScanner {
  public let id = "package-managers"
  public let displayName = "Package Managers"
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
    if let finding = makeFindingIfPackageCache(directoryURL), seenPaths.insert(finding.path).inserted {
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
      // allow .cache, .cargo, etc.
      if name.hasPrefix(".") && !["cache", "cargo", "pip"].contains(name.replacingOccurrences(of: ".", with: "")) {
        continue
      }
      guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
            values.isDirectory == true, values.isSymbolicLink == false, values.isPackage == false else {
        continue
      }
      scanDirectory(child.standardizedFileURL, currentDepth: currentDepth + 1, options: options, findings: &findings, seenPaths: &seenPaths)
    }
  }

  private func makeFindingIfPackageCache(_ directoryURL: URL) -> CleanupFinding? {
    let name = directoryURL.lastPathComponent
    let pathComponents = directoryURL.pathComponents

    let isPip = name == "pip" && directoryURL.pathComponents.dropLast().last == ".cache"
    let isCargoCache = name == "registry" && directoryURL.pathComponents.dropLast().last == ".cargo"
    let isGoCache = (name == "go-build" && pathComponents.contains("Caches")) || 
                    (name == "cache" && directoryURL.pathComponents.dropLast().last == "mod" && pathComponents.contains("go"))
    
    guard isPip || isCargoCache || isGoCache else { return nil }

    let estimatedBytes = CleanupSizing.directorySize(at: directoryURL)
    let itemCount = CleanupSizing.immediateChildCount(at: directoryURL)
    guard estimatedBytes > 0 else { return nil }

    let sizeSummary = CleanupSizing.byteCountString(for: estimatedBytes)

    var title = ""
    var subtitle = ""
    if isPip {
      title = "Python pip Cache"
      subtitle = "Downloaded python packages"
    } else if isCargoCache {
      title = "Rust Cargo Registry"
      subtitle = "Downloaded crates"
    } else if isGoCache {
      title = "Go Module Cache"
      subtitle = "Go build & mod cache"
    }

    return CleanupFinding(
      id: "\(id):\(directoryURL.path)",
      title: title,
      subtitle: subtitle,
      metadata: "\(itemCount) item(s) • \(sizeSummary) reclaimable",
      path: directoryURL.path,
      category: .packageManagers,
      sourceScanner: displayName,
      confidenceScore: 9,
      detectedBy: [title],
      detectedAt: Date(),
      estimatedBytes: estimatedBytes,
      cleanupTargets: [CleanupTargetDescriptor(name: "All contents", relativePath: ".")],
      recommendedAction: "Safe to remove. The package manager will automatically redownload packages upon next compile/install.",
      safetyLevel: .safeWithConfirmation
    )
  }
}
