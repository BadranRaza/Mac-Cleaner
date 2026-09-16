import AppKit

/// Bundle IDs of apps on this Mac, used to tell whether data belongs to an app that was removed.
struct InstalledApps: Sendable {
  let ids: Set<String>

  init(ids: Set<String>) { self.ids = ids }

  init() {
    let fm = FileManager.default
    let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                 fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
    var ids = Set<String>()
    for root in roots {
      for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        if name.hasSuffix(".app") {
          if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id) }
        } else if !name.hasPrefix(".") {
          // Vendor folders such as /Applications/Adobe Photoshop/.
          for inner in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] where inner.hasSuffix(".app") {
            if let id = Bundle(url: url.appendingPathComponent(inner))?.bundleIdentifier { ids.insert(id) }
          }
        }
      }
    }
    self.ids = ids
  }

  /// True when an app from the same vendor is installed (or LaunchServices knows the ID).
  /// Extensions and helpers often use IDs that differ from their app's, so the vendor is the safe unit.
  // ponytail: vendor = first two ID parts; an unrelated app from the same vendor keeps leftovers hidden.
  func hasApp(forID id: String) -> Bool {
    if ids.contains(id) || NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
    let vendor = Self.vendor(id)
    return ids.contains { Self.vendor($0) == vendor }
  }

  static func vendor(_ id: String) -> String {
    id.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
  }
}

extension Cleaner {
  /// Data from removed apps (exact bundle-ID folders only) and login items whose program is gone.
  func findLeftovers(apps: InstalledApps) -> [Pending] {
    var targets: [PendingTarget] = []
    let library = home.appendingPathComponent("Library")

    func isAppID(_ id: String) -> Bool {
      let lower = id.lowercased()
      return id.split(separator: ".").count >= 3 && !lower.contains("com.apple.") && !lower.hasPrefix("is.workflow")
    }
    func add(_ url: URL, id: String) {
      targets.append(PendingTarget(url: url, name: leftoverName(id), appID: nil, paths: [url]))
    }

    // Other apps' containers are privacy-protected; reading them without Full Disk Access shows a warning.
    if fullDiskAccess {
      for url in children(of: library.appendingPathComponent("Containers")) {
        let id = url.lastPathComponent
        if isAppID(id), !apps.hasApp(forID: id) { add(url, id: id) }
      }
      for url in children(of: library.appendingPathComponent("Group Containers")) {
        // "TEAMID1234.group.com.vendor.app", "group.com.vendor.app", "TEAMID1234.com.vendor.app"
        var parts = url.lastPathComponent.split(separator: ".").map(String.init)
        if let first = parts.first, first.count == 10, first == first.uppercased() { parts.removeFirst() }
        if let first = parts.first, first == "group" || first == "groups" { parts.removeFirst() }
        let id = parts.joined(separator: ".")
        if isAppID(id), !apps.hasApp(forID: id) { add(url, id: id) }
      }
    }
    // Application Support is skipped on purpose: command-line tools use app-like folder names there,
    // and it holds data (like app runtimes) that is painful to rebuild.

    for plist in children(of: library.appendingPathComponent("LaunchAgents")) where plist.pathExtension == "plist" {
      guard let program = loginItemProgram(plist), !FileManager.default.fileExists(atPath: program) else { continue }
      let name = (try? PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])?["Label"] as? String
      targets.append(PendingTarget(url: plist, name: "Login item \((name ?? plist.deletingPathExtension().lastPathComponent).split(separator: ".").last ?? "") · its program is gone",
                                   appID: nil, paths: [plist]))
    }

    guard !targets.isEmpty else { return [] }
    return [Pending(title: "Removed apps", category: .leftovers, location: library, targets: targets,
                    safety: .checkFirst, movesToTrash: true)]
  }

  /// The program a login item starts, when we can tell for sure that it's missing.
  func loginItemProgram(_ plist: URL) -> String? {
    guard let data = try? Data(contentsOf: plist),
          let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first,
          program.hasPrefix("/"), !program.hasPrefix("/Volumes/") else { return nil }
    // Without Full Disk Access, programs in protected folders look missing even when they exist.
    let protected = ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0).path + "/" }
    if !fullDiskAccess, protected.contains(where: program.hasPrefix) { return nil }
    return program
  }

  /// Claude Code keeps every plugin version it downloaded; only the ones in installed_plugins.json are used.
  func oldPluginVersions() -> [Pending] {
    let plugins = home.appendingPathComponent(".claude/plugins")
    guard let data = try? Data(contentsOf: plugins.appendingPathComponent("installed_plugins.json")),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let installed = json["plugins"] as? [String: [[String: Any]]] else { return [] }
    let inUse = Set(installed.values.flatMap { $0 }.compactMap { $0["installPath"] as? String })
    let weekAgo = Date().addingTimeInterval(-7 * 86_400)

    var targets: [PendingTarget] = []
    for marketplace in children(of: plugins.appendingPathComponent("cache")) {
      for plugin in children(of: marketplace) {
        let versions = children(of: plugin)
        // Only when a version of this plugin is in use, so we never remove the last copy.
        guard versions.contains(where: { inUse.contains($0.path) }) else { continue }
        for version in versions where !inUse.contains(version.path) {
          let modified = (try? version.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
          guard modified < weekAgo else { continue }  // a running session may still use a recent one
          targets.append(PendingTarget(url: version, name: "\(plugin.lastPathComponent) \(version.lastPathComponent)",
                                       appID: nil, paths: [version]))
        }
      }
    }
    guard !targets.isEmpty else { return [] }
    return [Pending(title: "Old Claude Code plugin versions", category: .developer, location: plugins.appendingPathComponent("cache"),
                    targets: targets, safety: .safe, movesToTrash: false)]
  }
}

/// "com.adguard.mac.adguard.loginhelper" → "Adguard", "com.nordvpn.NordVPN.NordLynx" → "NordLynx".
func leftoverName(_ id: String) -> String {
  let generic: Set<String> = ["mac", "macos", "osx", "app", "desktop", "helper", "loginhelper", "cli", "extension"]
  let parts = id.split(separator: ".").dropFirst().map(String.init)
  let name = parts.last { !generic.contains($0.lowercased()) } ?? parts.last ?? id
  return name.prefix(1).uppercased() + name.dropFirst()
}

/// Unloads a login item so it stops running before its file is moved away.
func stopLoginItem(_ plist: URL) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
  process.arguments = ["bootout", "gui/\(getuid())", plist.path]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try? process.run()
  process.waitUntilExit()
}
