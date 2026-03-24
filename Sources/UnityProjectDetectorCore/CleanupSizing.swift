import Foundation

enum CleanupSizing {
  static func byteCountString(for bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.countStyle = .file
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytes)
  }

  /// Calculates the total allocated size of all files under `url`, recursively.
  /// Always counts hidden files and directories — sizing must reflect the
  /// real disk footprint that cleanup would reclaim.
  static func directorySize(at url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
      options: [],
      errorHandler: { _, _ in true }
    ) else {
      return 0
    }

    var totalBytes: Int64 = 0

    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
        continue
      }

      if values.isDirectory == true {
        continue
      }

      let fileBytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
      totalBytes += Int64(fileBytes)
    }

    return totalBytes
  }

  static func directoryExists(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  static func immediateChildCount(at url: URL) -> Int {
    guard let children = try? FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.nameKey],
      options: []
    ) else {
      return 0
    }

    return children.count
  }
}
