import CryptoKit
import Foundation

extension Cleaner {
  /// Large files in Desktop, Documents and Downloads that exist more than once.
  /// Copies that share disk space (APFS clones, hard links) are ignored: removing them frees nothing.
  func findDuplicates(minimumBytes: Int64 = 50_000_000) -> [Pending] {
    guard fullDiskAccess else { return [] }
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .fileContentIdentifierKey, .fileResourceIdentifierKey,
                                     .creationDateKey, .isUbiquitousItemKey]
    struct File { let url: URL; let size: Int64; let content: Int64?; let created: Date }

    var bySize: [Int64: [File]] = [:]
    for folder in ["Desktop", "Documents", "Downloads"] {
      guard let walker = FileManager.default.enumerator(
        at: home.appendingPathComponent(folder), includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else { continue }
      for case let url as URL in walker {
        if Task.isCancelled { return [] }
        if url.lastPathComponent == "node_modules" { walker.skipDescendants(); continue }
        // iCloud files may not be on this Mac; reading them would download them.
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
              values.isUbiquitousItem != true, let size = values.fileSize, Int64(size) >= minimumBytes else { continue }
        bySize[Int64(size), default: []].append(File(url: url, size: Int64(size), content: values.fileContentIdentifier,
                                                     created: values.creationDate ?? .distantPast))
      }
    }

    var found: [Pending] = []
    for files in bySize.values where files.count > 1 {
      // One file per shared data stream: clones point at the same blocks. Keep the likely original,
      // oldest first; clones keep the original's date, so the shorter path breaks the tie.
      var seenContent = Set<Int64>()
      let distinct = files
        .sorted { ($0.created, $0.url.path.count) < ($1.created, $1.url.path.count) }
        .filter { $0.content.map { seenContent.insert($0).inserted } ?? true }
      guard distinct.count > 1 else { continue }

      for same in Dictionary(grouping: distinct, by: { fingerprint($0.url) }).values where same.count > 1 {
        if Task.isCancelled { return [] }
        let sorted = same.sorted { ($0.created, $0.url.path.count) < ($1.created, $1.url.path.count) }
        let original = sorted[0].url
        let copies = sorted.dropFirst().map { copy in
          PendingTarget(url: copy.url, name: copy.url.path.replacingOccurrences(of: home.path + "/", with: ""), appID: nil, paths: [copy.url])
        }
        found.append(Pending(title: original.lastPathComponent, category: .duplicates, location: original,
                             targets: copies, safety: .checkFirst, movesToTrash: true))
      }
    }
    return found
  }
}

/// SHA-256 of the whole file, streamed so memory stays flat.
// ponytail: hashes every same-size candidate fully; hash the first MB first if big folders get slow.
func fingerprint(_ url: URL) -> String {
  guard let handle = try? FileHandle(forReadingFrom: url) else { return UUID().uuidString }
  defer { try? handle.close() }
  var hasher = SHA256()
  while let chunk = try? handle.read(upToCount: 4_000_000), !chunk.isEmpty {
    if Task.isCancelled { return UUID().uuidString }
    hasher.update(data: chunk)
  }
  return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
