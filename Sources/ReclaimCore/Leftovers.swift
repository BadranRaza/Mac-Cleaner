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

  /// True when an installed app has this ID or a related one (its extension or helper, e.g.
  /// "com.maker.app.widget" for "com.maker.app"), or LaunchServices knows the ID.
  /// `sameVendor` also counts any app from the same maker: helpers and shared folders often use IDs
  /// unrelated to their app's (e.g. "com.openai.sky.CUAService" for ChatGPT).
  func hasApp(forID id: String, sameVendor: Bool = true) -> Bool {
    let id = id.lowercased()
    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
    let vendor = id.split(separator: ".").prefix(2).joined(separator: ".")
    return ids.contains { installed in
      let installed = installed.lowercased()
      return installed == id || id.hasPrefix(installed + ".") || installed.hasPrefix(id + ".")
        || (sameVendor && installed.split(separator: ".").prefix(2).joined(separator: ".") == vendor)
    }
  }
}

/// Tools that keep data outside ~/Library (hidden folders) or under a plain name in Application Support.
/// Removed apps from big makers (Google, Microsoft) would hide behind the maker's other apps,
/// so these are recognized explicitly.
struct KnownTool {
  let name: String
  let appIDs: [String]
  let commands: [String]
  let paths: [String]
  /// App names that also count as installed, e.g. "Gemini" for a Gemini app from anywhere.
  var appNames: [String] = []

  static let all: [KnownTool] = [
    // ~/.gemini belongs to Gemini CLI and Antigravity; Gemini in Chrome keeps its data inside Chrome's profile.
    KnownTool(name: "Antigravity and Gemini CLI", appIDs: ["com.google.antigravity", "com.google.antigravity-ide"], commands: ["gemini"],
              paths: [".antigravity", ".antigravity-ide", ".gemini", "Library/Application Support/Antigravity",
                      "Library/Application Support/Antigravity IDE"],
              appNames: ["Antigravity", "Antigravity IDE", "Gemini"]),
    KnownTool(name: "Cursor", appIDs: ["com.todesktop.230313mzl4w4u92"], commands: ["cursor"],
              paths: [".cursor", "Library/Application Support/Cursor"]),
    KnownTool(name: "Windsurf", appIDs: ["com.exafunction.windsurf"], commands: ["windsurf"],
              paths: [".windsurf", ".codeium", "Library/Application Support/Windsurf"]),
    KnownTool(name: "Trae", appIDs: ["com.trae.app"], commands: ["trae"],
              paths: [".trae", ".trae-cn", "Library/Application Support/Trae", "Library/Application Support/Trae CN"]),
    KnownTool(name: "Kiro", appIDs: ["dev.kiro.desktop"], commands: ["kiro"], paths: [".kiro", "Library/Application Support/Kiro"]),
    KnownTool(name: "Visual Studio Code", appIDs: ["com.microsoft.VSCode"], commands: ["code"],
              paths: [".vscode", "Library/Application Support/Code"]),
    KnownTool(name: "Zed", appIDs: ["dev.zed.Zed"], commands: ["zed"], paths: ["Library/Application Support/Zed"]),
    KnownTool(name: "GitKraken", appIDs: ["com.axosoft.gitkraken"], commands: ["gitkraken"],
              paths: [".gitkraken", "Library/Application Support/GitKraken"]),
    KnownTool(name: "BrowserStack Local", appIDs: [], commands: ["BrowserStackLocal", "browserstack-local"], paths: [".browserstack"]),
    KnownTool(name: "Visual Studio for Mac", appIDs: ["com.microsoft.visual-studio"], commands: [],
              paths: [".ServiceHub", "Library/Application Support/VisualStudio"]),
    KnownTool(name: "Plastic SCM", appIDs: ["com.codicesoftware.plasticscm"], commands: ["cm", "plastic"],
              paths: [".plastic4", "Library/Application Support/PlasticSCM"]),
    KnownTool(name: "Ollama", appIDs: ["com.electron.ollama"], commands: ["ollama"], paths: [".ollama", "Library/Application Support/Ollama"]),
  ]
}

/// Whether a command-line tool is installed. Apps started from Finder get a short PATH, so common tool folders are added.
func commandExists(_ name: String, home: URL) -> Bool {
  let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
  let common = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + [".local/bin", ".cargo/bin", ".npm-global/bin", ".bun/bin"].map { home.appendingPathComponent($0).path }
  return (path + common).contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }
}

/// Home folders that no account uses any more, e.g. kept when an account was deleted.
func deletedAccountFolders(in users: URL = URL(fileURLWithPath: "/Users"), accountHomes: Set<String> = accountHomes()) -> [URL] {
  ((try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? [])
    .filter { !$0.hasPrefix(".") && !["Shared", "Deleted Users", "Guest"].contains($0) }
    .map { users.appendingPathComponent($0) }
    .filter { url in
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        && !accountHomes.contains(url.standardizedFileURL.path)
    }
}

func accountHomes() -> Set<String> {
  var homes = Set<String>()
  setpwent()
  while let entry = getpwent() { homes.insert(URL(fileURLWithPath: String(cString: entry.pointee.pw_dir)).standardizedFileURL.path) }
  endpwent()
  return homes
}

extension Cleaner {
  /// Data from removed apps, found by exact bundle ID, known tool folders, login items whose program is gone,
  /// and home folders of deleted accounts.
  func findLeftovers(apps: InstalledApps) -> [Pending] {
    let library = home.appendingPathComponent("Library")
    var byID: [String: [URL]] = [:]

    func isAppID(_ id: String) -> Bool {
      let parts = id.lowercased().split(separator: ".")
      return parts.count >= 3 && !parts.contains("apple") && !id.lowercased().hasPrefix("is.workflow")
    }
    func collect(_ folder: String, id: (URL) -> String?) {
      for url in children(of: library.appendingPathComponent(folder)) {
        if let id = id(url), isAppID(id), !apps.hasApp(forID: id) { byID[id, default: []].append(url) }
      }
    }

    // Other apps' containers are privacy-protected; reading them without Full Disk Access shows a warning.
    if fullDiskAccess {
      collect("Containers") { $0.lastPathComponent }
      collect("Group Containers") { url in
        // "TEAMID1234.group.com.vendor.app", "group.com.vendor.app", "TEAMID1234.com.vendor.app"
        var parts = url.lastPathComponent.split(separator: ".").map(String.init)
        if let first = parts.first, first.count == 10, first == first.uppercased() { parts.removeFirst() }
        if let first = parts.first, first == "group" || first == "groups" { parts.removeFirst() }
        return parts.joined(separator: ".")
      }
    }
    collect("Preferences") { $0.pathExtension == "plist" ? $0.deletingPathExtension().lastPathComponent : nil }
    collect("HTTPStorages") { $0.lastPathComponent.replacingOccurrences(of: ".binarycookies", with: "") }
    collect("WebKit") { $0.lastPathComponent }
    collect("Saved Application State") { $0.pathExtension == "savedState" ? $0.deletingPathExtension().lastPathComponent : nil }

    var targets: [PendingTarget] = byID.compactMap { id, urls in
      // Lone settings files are tiny and many belong to command-line tools; list apps that left real data.
      let hasData = urls.contains { $0.path.contains("/Containers/") || $0.path.contains("/Group Containers/") }
        || urls.reduce(Int64(0)) { $0 + allocatedSize(of: $1) } >= 1_000_000
      return hasData ? PendingTarget(url: urls[0], name: leftoverName(id), appID: nil, paths: urls) : nil
    }

    let claimed = Set(targets.flatMap(\.paths).map(\.path))
    for tool in KnownTool.all {
      let installed = tool.appIDs.contains { apps.hasApp(forID: $0, sameVendor: false) }
        || tool.commands.contains { commandExists($0, home: home) }
        || tool.appNames.contains { name in ["/Applications", home.appendingPathComponent("Applications").path].contains {
          exists(URL(fileURLWithPath: "\($0)/\(name).app")) } }
      guard !installed else { continue }
      // The tool's own folders plus the settings and web data it left under its app IDs.
      let byAppID = tool.appIDs.flatMap { id in
        ["Preferences/\(id).plist", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies", "WebKit/\(id)",
         "Saved Application State/\(id).savedState", "Caches/\(id)", "Logs/\(id)", "Containers/\(id)"].map { "Library/\($0)" }
      }
      let urls = (tool.paths + byAppID).map { home.appendingPathComponent($0) }.filter { exists($0) && !claimed.contains($0.path) }
      if !urls.isEmpty { targets.append(PendingTarget(url: urls[0], name: tool.name, appID: nil, paths: urls)) }
    }

    for plist in children(of: library.appendingPathComponent("LaunchAgents")) where plist.pathExtension == "plist" {
      guard let program = loginItemProgram(plist), !FileManager.default.fileExists(atPath: program) else { continue }
      let name = (try? PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])?["Label"] as? String
      targets.append(PendingTarget(url: plist, name: "Login item \((name ?? plist.deletingPathExtension().lastPathComponent).split(separator: ".").last ?? "") · its program is gone",
                                   appID: nil, paths: [plist]))
    }

    var found: [Pending] = []
    if !targets.isEmpty {
      found.append(Pending(title: "Removed apps", category: .leftovers, location: library, targets: targets,
                           safety: .checkFirst, movesToTrash: true))
    }
    // Only for the real home folder; another account's data is shown, never guessed at in tests or other roots.
    if home.deletingLastPathComponent().path == "/Users" {
      let accounts = deletedAccountFolders().map {
        PendingTarget(url: $0, name: "\($0.lastPathComponent) · account that was deleted", appID: nil, paths: [$0])
      }
      if !accounts.isEmpty {
        found.append(Pending(title: "Folders of deleted accounts", category: .leftovers, location: home.deletingLastPathComponent(),
                             targets: accounts, safety: .checkFirst, movesToTrash: true))
      }
    }
    return found
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
