import Foundation

/// Something big that Reclaim deliberately leaves alone, explained in plain words.
public struct Insight: Identifiable, Hashable, Sendable {
  public let title: String
  public let advice: String
  public let url: URL
  /// Nil when measuring would take too long (millions of tiny files).
  public let bytes: Int64?
  public var id: URL { url }
}

extension Cleaner {
  public func insights() async -> [Insight] {
    // (path relative to home, title, advice, measure size)
    let known: [(String, String, String, Bool)] = [
      (".colima", "Docker virtual machines", "Your containers and images. Clean up inside Docker with “docker system prune”.", true),
      (".docker", "Docker settings and build cache", "Clean up inside Docker with “docker builder prune”.", true),
      (".codex/sessions", "Codex conversation history", "Your past Codex chats. Only delete them if you won't need them again.", true),
      (".claude/projects", "Claude Code conversation history", "Your past Claude Code sessions. Only delete them if you won't need them again.", true),
      (".gemini/antigravity-browser-profile", "Antigravity browser profile", "Holds sign-ins for Antigravity's browser. Sign out there instead of deleting it.", true),
      (".ollama/models", "Ollama AI models", "Remove models you don't use with “ollama rm”.", true),
      (".cocoapods/repos", "CocoaPods library list", "Frees space with “pod repo remove trunk”; CocoaPods downloads what it needs later.", false),
      ("Library/Developer/CoreSimulator/Devices", "iPhone simulators", "Remove simulators you don't use in Xcode › Settings › Components.", true),
      ("Library/Application Support", "App data", "Settings and saved work of your apps. Use Uninstall to remove an app together with its data.", true),
      ("Library/Mobile Documents", "iCloud Drive files on this Mac", "In Finder, right-click files and choose Remove Download.", true),
    ]
    let found = known.filter { exists(home.appendingPathComponent($0.0)) }

    var insights = await withTaskGroup(of: Insight.self) { group in
      for (path, title, advice, measure) in found {
        group.addTask {
          let url = self.home.appendingPathComponent(path)
          return Insight(title: title, advice: advice, url: url, bytes: measure ? allocatedSize(of: url) : nil)
        }
      }
      var result: [Insight] = []
      for await insight in group where (insight.bytes ?? .max) > 100_000_000 { result.append(insight) }
      return result
    }

    let others = children(of: home.deletingLastPathComponent())
      .filter { !["Shared", home.lastPathComponent].contains($0.lastPathComponent) && !$0.lastPathComponent.hasPrefix(".") }
    if !others.isEmpty {
      insights.append(Insight(title: "Other accounts on this Mac (\(others.count))",
                              advice: "Their files are private to them. Each person can run Reclaim in their own account.",
                              url: home.deletingLastPathComponent(), bytes: nil))
    }
    return insights.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
  }
}
