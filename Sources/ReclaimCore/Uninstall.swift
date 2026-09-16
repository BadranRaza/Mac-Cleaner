import AppKit

public struct InstalledApp: Identifiable, Hashable, Sendable {
  public let url: URL
  public let name: String
  public let bundleID: String
  public var id: URL { url }

  public var lastUsed: Date? {
    NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
  }
}

extension Cleaner {
  /// Apps the user installed. Apple's apps and Reclaim itself are left out.
  public func installedApps() -> [InstalledApp] {
    let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    var bundles: [URL] = []
    for root in roots {
      for url in children(of: root) {
        if url.pathExtension == "app" {
          bundles.append(url)
        } else if !url.lastPathComponent.hasPrefix(".") {
          bundles += children(of: url).filter { $0.pathExtension == "app" }
        }
      }
    }
    let own = Bundle.main.bundleIdentifier
    return bundles.compactMap { url in
      guard let id = Bundle(url: url)?.bundleIdentifier, !id.hasPrefix("com.apple."), id != own else { return nil }
      return InstalledApp(url: url, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                          bundleID: id)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// The app plus the files it created, found by bundle ID (Safe) and by app name (Check first).
  public func uninstallPlan(for app: InstalledApp) async -> [Finding] {
    let library = home.appendingPathComponent("Library")
    let id = app.bundleID
    var byID: [URL] = [app.url]

    func named(_ folder: String, _ names: [String]) {
      byID += names.map { library.appendingPathComponent(folder).appendingPathComponent($0) }.filter(exists)
    }
    named("Application Support", [id])
    named("Caches", [id])
    named("Logs", [id])
    named("HTTPStorages", [id, "\(id).binarycookies"])
    named("WebKit", [id])
    named("Saved Application State", ["\(id).savedState"])
    named("Preferences", ["\(id).plist"])
    named("Cookies", ["\(id).binarycookies"])
    byID += children(of: library.appendingPathComponent("Preferences/ByHost")).filter { $0.lastPathComponent.hasPrefix("\(id).") }
    byID += children(of: library.appendingPathComponent("Application Scripts")).filter { $0.lastPathComponent.hasPrefix(id) }
    byID += children(of: library.appendingPathComponent("LaunchAgents"))
      .filter { $0.pathExtension == "plist" && $0.lastPathComponent.hasPrefix(id) }
    if fullDiskAccess {
      byID += children(of: library.appendingPathComponent("Containers"))
        .filter { $0.lastPathComponent == id || $0.lastPathComponent.hasPrefix("\(id).") }
      byID += children(of: library.appendingPathComponent("Group Containers"))
        .filter { $0.lastPathComponent.hasSuffix(".\(id)") || $0.lastPathComponent.hasSuffix(".group.\(id)") }
    }

    // Folders named like the app are probably its data, but a name can be shared, so they need a look.
    let byName = ["Application Support", "Caches", "Logs"]
      .map { library.appendingPathComponent($0).appendingPathComponent(app.name) }
      .filter { exists($0) && !byID.contains($0) }

    func finding(_ title: String, _ urls: [URL], _ safety: Safety) async -> Finding? {
      guard !urls.isEmpty else { return nil }
      let targets = await withTaskGroup(of: Target.self) { group in
        for url in urls {
          group.addTask {
            Target(url: url, name: self.describe(url, app: app), appID: url == app.url ? id : nil,
                   bytes: allocatedSize(of: url), paths: [url])
          }
        }
        var targets: [Target] = []
        for await target in group { targets.append(target) }
        return targets.sorted { $0.bytes > $1.bytes }
      }
      return Finding(title: title, category: .leftovers, location: app.url, targets: targets, safety: safety, movesToTrash: true)
    }

    var plan: [Finding] = []
    if let main = await finding(app.name, byID, .safe) { plan.append(main) }
    if let maybe = await finding("Possibly related", byName, .checkFirst) { plan.append(maybe) }
    return plan
  }

  /// Plain words for where an app's file lives.
  func describe(_ url: URL, app: InstalledApp) -> String {
    if url == app.url { return "\(app.name) app" }
    let parent = url.deletingLastPathComponent().lastPathComponent
    switch parent {
    case "Application Support": return "Saved data"
    case "Caches": return "Temporary files"
    case "Logs": return "Activity logs"
    case "Preferences": return "Settings"
    case "ByHost": return "Settings for this Mac"
    case "Saved Application State": return "Window positions"
    case "HTTPStorages" where url.pathExtension == "binarycookies", "Cookies": return "Cookies"
    case "HTTPStorages", "WebKit": return "Web data"
    case "Containers": return url.lastPathComponent == app.bundleID ? "App data" : "Extension data"
    case "Group Containers": return "Shared data"
    case "Application Scripts": return "Scripts"
    case "LaunchAgents": return "Starts at login"
    default: return url.lastPathComponent
    }
  }

  /// Quits the app, then moves it and the chosen files to the Trash.
  @MainActor
  public static func uninstall(_ app: InstalledApp, plan: [Finding]) async -> CleanResult {
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
      running.terminate()
      for _ in 0..<50 where !running.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
      if !running.isTerminated {
        var result = CleanResult()
        result.failures.append("\(app.name) didn't quit. Quit it and try again.")
        return result
      }
    }
    return await Task.detached { clean(plan) }.value
  }
}
