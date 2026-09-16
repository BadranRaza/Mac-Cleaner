import AppKit

public enum Category: String, CaseIterable, Sendable {
  case caches, logs, trash, xcode, developer, projects, mail

  public var title: String {
    switch self {
    case .caches: "App Caches"
    case .logs: "Logs"
    case .trash: "Trash"
    case .xcode: "Xcode"
    case .developer: "Developer Caches"
    case .projects: "Project Dependencies"
    case .mail: "Mail Attachments"
    }
  }

  public var symbol: String {
    switch self {
    case .caches: "internaldrive"
    case .logs: "doc.text"
    case .trash: "trash"
    case .xcode: "hammer"
    case .developer: "shippingbox"
    case .projects: "folder"
    case .mail: "envelope"
    }
  }
}

public struct Target: Hashable, Sendable {
  public let url: URL
  public let bytes: Int64
}

public struct Finding: Identifiable, Hashable, Sendable {
  public let title: String
  public let category: Category
  /// The folder shown to the user. Never removed itself; only `targets` are.
  public let location: URL
  public let targets: [Target]
  /// Rebuildable data that is selected by default.
  public let preselected: Bool
  /// Moved to the Trash instead of deleted, for things that are hard to get back.
  public let movesToTrash: Bool

  public var id: String { location.path }
  public var bytes: Int64 { targets.reduce(0) { $0 + $1.bytes } }
}

public struct CleanResult: Sendable {
  public var freedBytes: Int64 = 0
  public var trashedBytes: Int64 = 0
  public var failures: [String] = []
}

private struct Rule {
  let title: String
  let category: Category
  let path: String
  var preselected = true
  var movesToTrash = false
  var needsFullDiskAccess = false
  /// Skip the rule while this app runs; it may be writing there.
  var app: String? = nil
}

private struct Pending: Sendable {
  let title: String
  let category: Category
  let location: URL
  let targets: [URL]
  let preselected: Bool
  let movesToTrash: Bool
}

public struct Cleaner: Sendable {
  public let home: URL
  private let runningApps: Set<String>
  /// Without Full Disk Access, macOS prompts or shows "Data Access Blocked" when we touch
  /// other apps' data or Desktop/Documents/Downloads, so those locations are skipped.
  private let fullDiskAccess: Bool

  public init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    runningApps: Set<String> = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
    fullDiskAccess: Bool? = nil
  ) {
    self.home = home.standardizedFileURL
    self.runningApps = runningApps
    self.fullDiskAccess = fullDiskAccess ?? hasFullDiskAccess()
  }

  /// Fixed, well-known locations. A rule nested inside another rule's folder
  /// (e.g. Library/Caches/Homebrew) owns those files; the outer rule skips them.
  private static let rules: [Rule] = [
    Rule(title: "Xcode DerivedData", category: .xcode, path: "Library/Developer/Xcode/DerivedData",
         preselected: false, app: "com.apple.dt.Xcode"),
    Rule(title: "Simulator Caches", category: .xcode, path: "Library/Developer/CoreSimulator/Caches",
         app: "com.apple.iphonesimulator"),
    Rule(title: "iOS Device Support", category: .xcode, path: "Library/Developer/Xcode/iOS DeviceSupport",
         preselected: false),
    Rule(title: "Xcode Archives", category: .xcode, path: "Library/Developer/Xcode/Archives",
         preselected: false, movesToTrash: true),
    Rule(title: "Homebrew", category: .developer, path: "Library/Caches/Homebrew"),
    Rule(title: "CocoaPods", category: .developer, path: "Library/Caches/CocoaPods"),
    Rule(title: "pip", category: .developer, path: "Library/Caches/pip"),
    Rule(title: "Yarn", category: .developer, path: "Library/Caches/Yarn"),
    Rule(title: "Go build", category: .developer, path: "Library/Caches/go-build"),
    Rule(title: "npm", category: .developer, path: ".npm/_cacache"),
    Rule(title: "Cargo registry", category: .developer, path: ".cargo/registry/cache"),
    Rule(title: "Gradle", category: .developer, path: ".gradle/caches", preselected: false),
    Rule(title: "User caches", category: .caches, path: "Library/Caches"),
    Rule(title: "User logs", category: .logs, path: "Library/Logs"),
    Rule(title: "Trash", category: .trash, path: ".Trash", preselected: false, needsFullDiskAccess: true),
    Rule(title: "Mail Downloads", category: .mail,
         path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
         preselected: false, movesToTrash: true, needsFullDiskAccess: true),
  ]

  /// Cache folders that hold state or are very expensive to rebuild (prefix match).
  private static let protectedPrefixes = [
    "com.apple.FontRegistry", "com.apple.spotlight", "CloudKit", "com.apple.finder", "com.apple.bird",
    "com.apple.HomeKit", "com.apple.containermanagerd", "FamilyCircle", "JetBrains", "ms-playwright",
  ]

  /// Cache folders not named by their app's bundle ID.
  private static let cacheOwners = [
    "Google": "com.google.Chrome", "Firefox": "org.mozilla.firefox", "Mozilla": "org.mozilla.firefox",
    "BraveSoftware": "com.brave.Browser", "Microsoft Edge": "com.microsoft.edgemac", "Slack": "com.tinyspeck.slackmacgap",
  ]

  /// Home folders never worth walking for project dependencies.
  private static let skippedHomeFolders: Set<String> = ["Library", "Pictures", "Movies", "Music", "Applications"]
  private static let privacyProtectedFolders: Set<String> = ["Desktop", "Documents", "Downloads"]

  public func scan() async -> [Finding] {
    let claimed = Set(Self.rules.map { home.appendingPathComponent($0.path).path })
    var pending: [Pending] = []

    for rule in Self.rules where !runningApps.contains(rule.app ?? "") && (fullDiskAccess || !rule.needsFullDiskAccess) {
      let location = home.appendingPathComponent(rule.path)
      let targets = children(of: location).filter { !claimed.contains($0.path) && isCleanable($0) }
      if !targets.isEmpty {
        pending.append(Pending(title: rule.title, category: rule.category, location: location, targets: targets,
                               preselected: rule.preselected, movesToTrash: rule.movesToTrash))
      }
    }

    let containers = home.appendingPathComponent("Library/Containers")
    let containerCaches = !fullDiskAccess ? [] : children(of: containers)
      .filter { $0.lastPathComponent != "com.apple.mail" && isCleanable($0) }
      .flatMap { children(of: $0.appendingPathComponent("Data/Library/Caches")).filter(isCleanable) }
    if !containerCaches.isEmpty {
      pending.append(Pending(title: "Sandboxed app caches", category: .caches, location: containers,
                             targets: containerCaches, preselected: true, movesToTrash: false))
    }

    pending += findProjectArtifacts()
    if Task.isCancelled { return [] }

    return await withTaskGroup(of: Finding?.self) { group in
      for item in pending {
        group.addTask {
          var targets: [Target] = []
          for url in item.targets {
            if Task.isCancelled { return nil }
            targets.append(Target(url: url, bytes: allocatedSize(of: url)))
          }
          let finding = Finding(title: item.title, category: item.category, location: item.location,
                                targets: targets, preselected: item.preselected, movesToTrash: item.movesToTrash)
          return finding.bytes > 0 ? finding : nil
        }
      }
      var findings: [Finding] = []
      for await finding in group { if let finding { findings.append(finding) } }
      return Task.isCancelled ? [] : findings.sorted { $0.bytes > $1.bytes }
    }
  }

  /// Not protected, and not owned by a running app (cache and container folders are named by bundle ID).
  private func isCleanable(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    return !Self.protectedPrefixes.contains(where: name.hasPrefix)
      && !runningApps.contains(name) && !runningApps.contains(Self.cacheOwners[name] ?? "")
  }

  /// One walk over the home folder for per-project dependency and build folders.
  private func findProjectArtifacts() -> [Pending] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    guard let walker = FileManager.default.enumerator(
      at: home, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }

    var found: [Pending] = []
    func add(_ title: String, _ location: URL, _ targets: [URL]) {
      found.append(Pending(title: title, category: .projects, location: location, targets: targets,
                           preselected: false, movesToTrash: false))
      walker.skipDescendants()
    }

    for case let url as URL in walker {
      if Task.isCancelled { return [] }
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
            values.isDirectory == true, values.isSymbolicLink != true else { continue }

      let name = url.lastPathComponent
      if walker.level == 1, Self.skippedHomeFolders.contains(name)
        || (!fullDiskAccess && Self.privacyProtectedFolders.contains(name)) {
        walker.skipDescendants()
        continue
      }

      let parent = url.deletingLastPathComponent()
      if name == "node_modules", exists(parent.appendingPathComponent("package.json")) {
        add("\(parent.lastPathComponent) · node_modules", url, [url])
      } else if name == "Pods", exists(parent.appendingPathComponent("Podfile")) {
        add("\(parent.lastPathComponent) · Pods", url, [url])
      } else if exists(url.appendingPathComponent("ProjectSettings/ProjectVersion.txt")),
                exists(url.appendingPathComponent("Assets")) {
        let targets = ["Library", "Temp", "Obj", "Logs"].map { url.appendingPathComponent($0) }.filter(exists)
        if targets.isEmpty { walker.skipDescendants() } else { add("\(name) · Unity cache", url, targets) }
      }
    }
    return found
  }

  private func children(of url: URL) -> [URL] {
    // Built from names so paths stay comparable with rule paths (no /var vs /private/var surprises).
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).map { url.appendingPathComponent($0) }
  }

  private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  public static func clean(_ findings: [Finding]) -> CleanResult {
    var result = CleanResult()
    for finding in findings {
      for target in finding.targets {
        do {
          if finding.movesToTrash {
            try FileManager.default.trashItem(at: target.url, resultingItemURL: nil)
            result.trashedBytes += target.bytes
          } else {
            try FileManager.default.removeItem(at: target.url)
            result.freedBytes += target.bytes
          }
        } catch {
          result.failures.append("\(target.url.path): \(error.localizedDescription)")
        }
      }
    }
    return result
  }
}

/// Allocated bytes on disk, like `du`. Hard-linked files are counted once.
// ponytail: dedupe is per target, and APFS clones still count fully; sizes are an upper bound.
func allocatedSize(of url: URL) -> Int64 {
  let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey, .linkCountKey, .fileResourceIdentifierKey]
  guard let root = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey]) else { return 0 }
  guard root.isDirectory == true else { return Int64(root.totalFileAllocatedSize ?? 0) }
  guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                                    errorHandler: { _, _ in true }) else { return 0 }
  var total: Int64 = 0
  var seenLinks = Set<AnyHashable>()
  for case let file as URL in walker {
    if Task.isCancelled { return 0 }
    guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
    if (values.linkCount ?? 1) > 1, let id = values.fileResourceIdentifier as? AnyHashable,
       !seenLinks.insert(id).inserted { continue }
    total += Int64(values.totalFileAllocatedSize ?? 0)
  }
  return total
}

/// Full Disk Access probe. The system TCC.db exists on every Mac, belongs to no app, and only
/// opens with FDA, so probing it never triggers a prompt. (The per-user TCC.db is not always present.)
public func hasFullDiskAccess() -> Bool {
  guard let handle = FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") else { return false }
  try? handle.close()
  return true
}
