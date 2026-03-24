import Foundation

enum ScanRootBookmarkStore {
  private static let defaultsKey = "scan-root-bookmarks"

  static func loadURLs() -> [URL] {
    guard let bookmarkDataList = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] else {
      return []
    }

    var urls: [URL] = []
    var updatedBookmarkDataList: [Data] = []
    var seenPaths = Set<String>()
    var didChangeStoredData = false

    for bookmarkData in bookmarkDataList {
      do {
        var isStale = false
        let resolvedURL = try URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        ).standardizedFileURL

        let path = resolvedURL.path
        guard seenPaths.insert(path).inserted else {
          didChangeStoredData = true
          continue
        }

        urls.append(resolvedURL)

        if isStale, let refreshedBookmarkData = makeBookmarkData(for: resolvedURL) {
          updatedBookmarkDataList.append(refreshedBookmarkData)
          didChangeStoredData = true
        } else {
          updatedBookmarkDataList.append(bookmarkData)
        }
      } catch {
        didChangeStoredData = true
      }
    }

    if didChangeStoredData {
      persist(bookmarkDataList: updatedBookmarkDataList)
    }

    return urls
  }

  static func save(urls: [URL]) {
    let uniqueURLs = deduplicated(urls: urls)
    let bookmarkDataList = uniqueURLs.compactMap(makeBookmarkData(for:))
    persist(bookmarkDataList: bookmarkDataList)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: defaultsKey)
  }

  private static func persist(bookmarkDataList: [Data]) {
    UserDefaults.standard.set(bookmarkDataList, forKey: defaultsKey)
  }

  private static func deduplicated(urls: [URL]) -> [URL] {
    var seenPaths = Set<String>()
    var result: [URL] = []

    for url in urls.map(\.standardizedFileURL) {
      if seenPaths.insert(url.path).inserted {
        result.append(url)
      }
    }

    return result
  }

  private static func makeBookmarkData(for url: URL) -> Data? {
    let standardizedURL = url.standardizedFileURL
    let startedAccess = standardizedURL.startAccessingSecurityScopedResource()

    defer {
      if startedAccess {
        standardizedURL.stopAccessingSecurityScopedResource()
      }
    }

    return try? standardizedURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }
}
