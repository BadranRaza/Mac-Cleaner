import Foundation
import ReclaimCore

// Lists what Reclaim would clean. Read-only.
let findings = await Cleaner().scan()
let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }

if !hasFullDiskAccess() {
  print("Note: no Full Disk Access; Trash, Mail, app containers and Desktop/Documents/Downloads are skipped.\n")
}
for finding in findings {
  let mark = finding.preselected ? "●" : "○"
  print("\(mark) \(size(finding.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(finding.category.title) · \(finding.title)")
  print("    \(finding.location.path)")
}
print("\nTotal: up to \(size(findings.reduce(0) { $0 + $1.bytes })) (● selected by default)")
