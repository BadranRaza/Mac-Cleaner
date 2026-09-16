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
  print("\(mark) \(size(finding.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(finding.category.title) · \(finding.title) [\(finding.safety.title)]")
  for target in finding.targets.prefix(ProcessInfo.processInfo.environment["ALL"] != nil ? 999 : 5) {
    print("    \(target.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(size(target.bytes))")
  }
  if finding.targets.count > 5, ProcessInfo.processInfo.environment["ALL"] == nil { print("    … \(finding.targets.count - 5) more") }
}
let insights = await Cleaner().insights()
if !insights.isEmpty { print("\nAlso taking space (left alone):") }
for insight in insights {
  print("  \((insight.bytes.map(size) ?? "large").padding(toLength: 10, withPad: " ", startingAt: 0)) \(insight.title) — \(insight.advice)")
}
print("\nTotal: up to \(size(findings.reduce(0) { $0 + $1.bytes })) (● selected by default)")
