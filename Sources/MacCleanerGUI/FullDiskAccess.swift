import AppKit
import Foundation

enum FullDiskAccessStatus: Equatable {
  case granted
  case missing
}

enum FullDiskAccess {
  static let missingStatusMessage =
    "System-wide scans require Full Disk Access. In System Settings, open Privacy & Security > Full Disk Access, add MacCleaner.app, turn it on, then return here."

  static let setupSteps = [
    "Open System Settings > Privacy & Security > Full Disk Access.",
    "Add MacCleaner.app from your Applications folder and enable the toggle.",
    "Return to Mac Cleaner and start the scan again. Relaunch the app if macOS asks."
  ]

  // macOS does not expose a public Full Disk Access status API for desktop apps,
  // so we probe a few protected locations before allowing a system-wide scan.
  static func currentStatus(fileManager: FileManager = .default) -> FullDiskAccessStatus {
    let probeURLs = protectedProbeURLs(fileManager: fileManager)

    for url in probeURLs where canReadProbe(at: url, fileManager: fileManager) {
      return .granted
    }

    return .missing
  }

  static func openSystemSettings() {
    let candidates = [
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
      URL(string: "x-apple.systempreferences:com.apple.preference.security"),
      URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane")
    ]

    for url in candidates.compactMap({ $0 }) {
      if NSWorkspace.shared.open(url) {
        return
      }
    }
  }

  private static func protectedProbeURLs(fileManager: FileManager) -> [URL] {
    let homeURL = fileManager.homeDirectoryForCurrentUser

    return [
      homeURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("com.apple.TCC", isDirectory: true)
        .appendingPathComponent("TCC.db", isDirectory: false),
      homeURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Mail", isDirectory: true),
      homeURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Safari", isDirectory: true),
      homeURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Messages", isDirectory: true)
    ]
  }

  private static func canReadProbe(at url: URL, fileManager: FileManager) -> Bool {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return false
    }

    if isDirectory.boolValue {
      return (try? fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.nameKey],
        options: [.skipsHiddenFiles]
      )) != nil
    }

    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return false
    }

    defer {
      try? handle.close()
    }

    return (try? handle.read(upToCount: 1)) != nil
  }
}
