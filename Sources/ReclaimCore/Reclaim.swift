import AppKit

public enum Category: String, CaseIterable, Sendable {
  // Declaration order is the order in the app.
  case caches, logs, trash, mail, developer, xcode, unity, nodeModules, pods

  public var title: String {
    switch self {
    case .caches: "Temporary App Files"
    case .logs: "Activity Logs"
    case .trash: "Trash"
    case .mail: "Email Attachments"
    case .developer: "Developer Downloads"
    case .xcode: "Xcode"
    case .unity: "Unity Projects"
    case .nodeModules: "JavaScript Packages"
    case .pods: "iOS Libraries"
    }
  }

  /// One plain sentence: what it is and what happens if you remove it.
  public var summary: String {
    switch self {
    case .caches: "Files apps keep so they open faster. Apps quietly make new ones when needed."
    case .logs: "Records apps write about what they did. Nothing needs them."
    case .trash: "Things you already deleted. Emptying the Trash can't be undone."
    case .mail: "Attachments Mail saved. They download again when you open the email."
    case .developer: "Downloads kept by developer tools. They download again when needed."
    case .xcode: "Files Xcode makes while building apps. Rebuilding them takes a while."
    case .unity: "Files Unity rebuilds when you reopen a project, and your exported builds."
    case .nodeModules: "Packages downloaded for JavaScript projects. Reinstall with npm install."
    case .pods: "Libraries downloaded for iOS projects. Reinstall with pod install."
    }
  }

  public var symbol: String {
    switch self {
    case .caches: "app.badge"
    case .logs: "list.bullet.rectangle"
    case .trash: "trash"
    case .mail: "paperclip"
    case .developer: "arrow.down.circle"
    case .xcode: "hammer"
    case .unity: "cube"
    case .nodeModules: "curlybraces"
    case .pods: "square.stack.3d.up"
    }
  }
}

/// What removing something costs you. Only `.safe` items are selected by default.
public enum Safety: Int, Comparable, CaseIterable, Sendable {
  case safe, takesTime, checkFirst

  public static func < (a: Safety, b: Safety) -> Bool { a.rawValue < b.rawValue }

  public var title: String {
    switch self {
    case .safe: "Safe"
    case .takesTime: "Takes time"
    case .checkFirst: "Check first"
    }
  }

  public var explanation: String {
    switch self {
    case .safe: "Comes back by itself. You won't notice it's gone."
    case .takesTime: "Comes back, but rebuilding or downloading it takes a while."
    case .checkFirst: "May be your only copy. Look before you remove it."
    }
  }
}

public struct Target: Hashable, Sendable {
  /// Identifies the item in the app and is what "Show in Finder" reveals.
  public let url: URL
  /// Friendly name, e.g. the app that owns a cache.
  public let name: String
  /// Bundle ID of the owning app, for its icon.
  public let appID: String?
  public let bytes: Int64
  /// What cleaning removes. Usually just `url`; for grouped items, the contents of `url`.
  let paths: [URL]
}

public struct Finding: Identifiable, Hashable, Sendable {
  public let title: String
  public let category: Category
  public let location: URL
  public let targets: [Target]
  public let safety: Safety
  /// Moved to the Trash instead of deleted, for things that are hard to get back.
  public let movesToTrash: Bool

  public var id: String { "\(title)|\(location.path)" }
  public var bytes: Int64 { targets.reduce(0) { $0 + $1.bytes } }
  public var preselected: Bool { safety == .safe }

  /// The same finding limited to the chosen targets.
  public func only(_ urls: Set<URL>) -> Finding {
    Finding(title: title, category: category, location: location, targets: targets.filter { urls.contains($0.url) },
            safety: safety, movesToTrash: movesToTrash)
  }
}

public struct CleanResult: Sendable {
  public var freedBytes: Int64 = 0
  public var trashedBytes: Int64 = 0
  public var failures: [String] = []

  public init() {}
}

private struct Rule {
  let title: String
  let category: Category
  let path: String
  var safety = Safety.safe
  /// List each item inside (apps, projects, iOS versions) instead of one row for the whole folder.
  var perItem = false
  var movesToTrash = false
  var needsFullDiskAccess = false
  /// Skip the rule while this app runs; it may be writing there.
  var app: String? = nil
}

private struct PendingTarget: Sendable {
  let url: URL
  let name: String
  let appID: String?
  let paths: [URL]
}

private struct Pending: Sendable {
  let title: String
  let category: Category
  let location: URL
  let targets: [PendingTarget]
  let safety: Safety
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
    Rule(title: "Build files", category: .xcode, path: "Library/Developer/Xcode/DerivedData",
         safety: .takesTime, perItem: true, app: "com.apple.dt.Xcode"),
    Rule(title: "Simulator files", category: .xcode, path: "Library/Developer/CoreSimulator/Caches",
         app: "com.apple.iphonesimulator"),
    Rule(title: "iPhone debugging files", category: .xcode, path: "Library/Developer/Xcode/iOS DeviceSupport",
         safety: .takesTime, perItem: true),
    Rule(title: "Archived app builds", category: .xcode, path: "Library/Developer/Xcode/Archives",
         safety: .checkFirst, perItem: true, movesToTrash: true),
    Rule(title: "Homebrew", category: .developer, path: "Library/Caches/Homebrew"),
    Rule(title: "CocoaPods", category: .developer, path: "Library/Caches/CocoaPods"),
    Rule(title: "Python (pip)", category: .developer, path: "Library/Caches/pip"),
    Rule(title: "Yarn", category: .developer, path: "Library/Caches/Yarn"),
    Rule(title: "Go", category: .developer, path: "Library/Caches/go-build"),
    Rule(title: "npm", category: .developer, path: ".npm/_cacache"),
    Rule(title: "Rust (Cargo)", category: .developer, path: ".cargo/registry/cache"),
    Rule(title: "Gradle", category: .developer, path: ".gradle/caches", safety: .takesTime),
    Rule(title: "Your apps", category: .caches, path: "Library/Caches", perItem: true),
    Rule(title: "Activity logs", category: .logs, path: "Library/Logs"),
    Rule(title: "Items in Trash", category: .trash, path: ".Trash", safety: .checkFirst, needsFullDiskAccess: true),
    Rule(title: "Email attachments", category: .mail,
         path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
         safety: .checkFirst, movesToTrash: true, needsFullDiskAccess: true),
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
      let items = children(of: location).filter { !claimed.contains($0.path) && isCleanable($0) }
      guard !items.isEmpty else { continue }
      let targets = rule.perItem
        ? items.map { item in
            let appID = owner(of: item.lastPathComponent)
            return PendingTarget(url: item, name: friendlyName(item.lastPathComponent, appID: appID), appID: appID, paths: [item])
          }
        : [PendingTarget(url: location, name: rule.title, appID: nil, paths: items)]
      pending.append(Pending(title: rule.title, category: rule.category, location: location, targets: targets,
                             safety: rule.safety, movesToTrash: rule.movesToTrash))
    }

    // Apps from the App Store keep their caches inside their own container; one row per app.
    let containers = home.appendingPathComponent("Library/Containers")
    let containerTargets: [PendingTarget] = !fullDiskAccess ? [] : children(of: containers)
      .filter { $0.lastPathComponent != "com.apple.mail" && isCleanable($0) }
      .compactMap { container in
        let caches = container.appendingPathComponent("Data/Library/Caches")
        let items = children(of: caches).filter(isCleanable)
        guard !items.isEmpty else { return nil }
        let appID = container.lastPathComponent
        return PendingTarget(url: caches, name: friendlyName(appID, appID: appID), appID: appID, paths: items)
      }
    if !containerTargets.isEmpty {
      pending.append(Pending(title: "App Store apps", category: .caches, location: containers,
                             targets: containerTargets, safety: .safe, movesToTrash: false))
    }

    pending += findProjectArtifacts()
    if Task.isCancelled { return [] }

    return await withTaskGroup(of: Finding?.self) { group in
      for item in pending {
        group.addTask {
          var targets: [Target] = []
          for target in item.targets {
            if Task.isCancelled { return nil }
            let bytes = target.paths.reduce(Int64(0)) { $0 + allocatedSize(of: $1) }
            if bytes > 0 {
              targets.append(Target(url: target.url, name: target.name, appID: target.appID, bytes: bytes, paths: target.paths))
            }
          }
          guard !targets.isEmpty else { return nil }
          return Finding(title: item.title, category: item.category, location: item.location,
                         targets: targets.sorted { $0.bytes > $1.bytes }, safety: item.safety, movesToTrash: item.movesToTrash)
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

  private func owner(of folderName: String) -> String? {
    Self.cacheOwners[folderName] ?? (folderName.contains(".") ? folderName : nil)
  }

  /// One walk over the home folder for per-project dependency and build folders.
  private func findProjectArtifacts() -> [Pending] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    guard let walker = FileManager.default.enumerator(
      at: home, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }

    var found: [Pending] = []
    func add(_ title: String, _ category: Category, _ location: URL, _ urls: [URL], _ safety: Safety, trash: Bool = false) {
      guard !urls.isEmpty else { return }
      let targets = urls.map { PendingTarget(url: $0, name: urls.count == 1 ? title : $0.lastPathComponent, appID: nil, paths: [$0]) }
      found.append(Pending(title: title, category: category, location: location, targets: targets,
                           safety: safety, movesToTrash: trash))
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
        add(parent.lastPathComponent, .nodeModules, url, [url], .takesTime)
        walker.skipDescendants()
      } else if name == "Pods", exists(parent.appendingPathComponent("Podfile")) {
        add(parent.lastPathComponent, .pods, url, [url], .takesTime)
        walker.skipDescendants()
      } else if exists(url.appendingPathComponent("ProjectSettings/ProjectVersion.txt")),
                exists(url.appendingPathComponent("Assets")) {
        let inProject = { (names: [String]) in names.map { url.appendingPathComponent($0) }.filter(self.exists) }
        add("\(name) · rebuildable files", .unity, url, inProject(["Library", "Temp", "Obj", "Logs"]), .takesTime)
        // Builds may be the only copy of a release, so they go to the Trash.
        add("\(name) · exported builds", .unity, url, inProject(["Build", "Builds"]), .checkFirst, trash: true)
        walker.skipDescendants()
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
        var failed = false
        for path in target.paths {
          do {
            if finding.movesToTrash {
              try FileManager.default.trashItem(at: path, resultingItemURL: nil)
            } else {
              try FileManager.default.removeItem(at: path)
            }
          } catch {
            failed = true
            result.failures.append("\(path.path): \(error.localizedDescription)")
          }
        }
        // ponytail: a partly failed item counts as not freed; per-path sizes if totals need to be exact.
        if !failed {
          if finding.movesToTrash { result.trashedBytes += target.bytes } else { result.freedBytes += target.bytes }
        }
      }
    }
    return result
  }
}

/// "com.spotify.client" → "Spotify" (installed app name), "MyApp-bxkqzyr…" → "MyApp", "org.swift.swiftpm" → "swiftpm".
func friendlyName(_ folderName: String, appID: String?) -> String {
  if let appID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) {
    return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
  }
  // Xcode DerivedData folders end in a 28-character hash.
  if let dash = folderName.lastIndex(of: "-"), folderName.distance(from: dash, to: folderName.endIndex) == 29 {
    return String(folderName[..<dash])
  }
  let parts = folderName.split(separator: ".")
  return parts.count >= 3 ? String(parts.last!) : folderName
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
