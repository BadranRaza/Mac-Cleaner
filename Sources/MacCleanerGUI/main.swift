import SwiftUI
import AppKit
import MacCleanerCore

@main
struct MacCleanerGUI: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var scanStore = ScanStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(scanStore)
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 1024, height: 760)
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

private struct ContentView: View {
  @EnvironmentObject var scanStore: ScanStore

  var body: some View {
    ZStack {
      AppBackdrop()

      ScrollView {
        VStack(spacing: 18) {
          HeaderCard()
          ScanControlCard()

          if scanStore.isScanning {
            ProgressPanel()
              .transition(.opacity.combined(with: .move(edge: .top)))
          }

          if let report = scanStore.lastReport {
            SummaryCard(report: report)
            ResultsCard(items: report.items)
          } else {
            EmptyStateCard()
          }
        }
        .padding(24)
        .padding(.bottom, 24)
      }
    }
    .frame(minWidth: 900, minHeight: 640)
  }
}

private struct AppBackdrop: View {
  var body: some View {
    ZStack {
      Color(nsColor: NSColor.windowBackgroundColor)
        .ignoresSafeArea()

      VStack {
        Spacer()
        Circle()
          .fill(
            RadialGradient(
              colors: [
                Color.accentColor.opacity(0.08),
                Color.clear
              ],
              center: .top,
              startRadius: 0,
              endRadius: 580
            )
          )
          .frame(width: 700, height: 700)
          .offset(x: -240, y: 20)
        Spacer()
      }
      .ignoresSafeArea()
    }
  }
}

private struct MacPanel<Content: View>: View {
  private let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    content()
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.regularMaterial)
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.35), lineWidth: 1)
          )
      )
  }
}

private struct HeaderCard: View {
  var body: some View {
    MacPanel {
      VStack(alignment: .leading, spacing: 6) {
        Text("Mac Cleaner")
          .font(.system(size: 32, weight: .bold, design: .rounded))

        Text("General Cleanup Scanner")
          .font(.system(size: 22, weight: .medium, design: .rounded))
          .foregroundStyle(.secondary)

        Text("Scan user-selected folders for reclaimable development artifacts. Unity project cleanup is available as one scanner.")
          .font(.system(size: 16, weight: .regular, design: .rounded))
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct ScanControlCard: View {
  @EnvironmentObject var scanStore: ScanStore
  @State private var showAdvancedOptions = false

  var body: some View {
    MacPanel {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Scan setup")
            .font(.system(size: 22, weight: .semibold, design: .rounded))

          Text("Select the folders Mac Cleaner is allowed to inspect, then tune detection options.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            Text("Scan folders")
              .font(.headline)

            Spacer()

            Button {
              scanStore.addScanRoots()
            } label: {
              Label("Add folders", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
              scanStore.clearScanRoots()
            } label: {
              Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(scanStore.selectedRoots.isEmpty)
          }

          if scanStore.selectedRoots.isEmpty {
            Text("Add at least one folder. Mac Cleaner only scans user-approved locations.")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.vertical, 6)
              .help("Choose the folders you want Mac Cleaner to inspect.")
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(scanStore.selectedRoots, id: \.self) { root in
                  ScanRootRow(url: root) {
                    scanStore.removeSelectedRoot(root)
                  }
                }
              }
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(Color(nsColor: NSColor.textBackgroundColor).opacity(0.5))
            .overlay(
              RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
          }
        }

        Divider()

        HStack(spacing: 16) {
          LabeledContent("Min confidence") {
            TextField("6", text: $scanStore.minimumConfidence)
              .textFieldStyle(.roundedBorder)
              .frame(width: 100)
          }

          LabeledContent("Search depth") {
            TextField("Unlimited", text: $scanStore.maxDepth)
              .textFieldStyle(.roundedBorder)
              .frame(width: 130)
          }
        }

        DisclosureGroup("Advanced options", isExpanded: $showAdvancedOptions) {
          VStack(alignment: .leading, spacing: 10) {
            Toggle("Scan hidden folders", isOn: $scanStore.includeHidden)
            Toggle("Follow folder shortcuts", isOn: $scanStore.followSymlinks)
            Text("We only scan the folders you add here.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.top, 4)
        }

        HStack {
          if !scanStore.isInputValid && !scanStore.minimumConfidence.isEmpty {
            Text("Minimum confidence should be between 0 and 10.")
              .font(.footnote)
              .foregroundStyle(.red)
          }
          Spacer()
          Button {
            scanStore.scan()
          } label: {
            Label(scanStore.isScanning ? "Scanning..." : "Run scan", systemImage: "magnifyingglass")
              .font(.system(size: 16, weight: .semibold, design: .rounded))
              .frame(width: 132)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
          .keyboardShortcut(.defaultAction)
          .disabled(scanStore.isScanning || !scanStore.canScan)
        }
      }
    }
  }
}

private struct ScanRootRow: View {
  let url: URL
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "folder.fill")
        .foregroundStyle(.blue)
      Text(url.path)
        .font(.system(size: 16, design: .monospaced))
        .foregroundStyle(.primary)
        .lineLimit(1)
      Spacer(minLength: 6)
      Button {
        onRemove()
      } label: {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Remove folder")
    }
  }
}

private struct ProgressPanel: View {
  @EnvironmentObject var scanStore: ScanStore

  var body: some View {
    MacPanel {
      HStack(alignment: .center, spacing: 12) {
        ProgressView()
          .controlSize(.large)
          .scaleEffect(0.9)
        Text(scanStore.status)
          .font(.system(size: 16, design: .rounded))
          .foregroundStyle(.secondary)
        Spacer()
      }
    }
  }
}

private struct SummaryCard: View {
  let report: CleanupScanReport

  var body: some View {
    MacPanel {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Scan summary")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
          Text("Scanned at \(report.scannedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("Roots: \(report.scannedRoots.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        ScoreBadge(value: report.summary["high", default: 0], title: "High", color: .green)
        ScoreBadge(value: report.summary["medium", default: 0], title: "Medium", color: .yellow)
        ScoreBadge(value: report.summary["low", default: 0], title: "Low", color: .orange)
        ScoreBadge(value: report.summary["total", default: 0], title: "Total", color: .blue)
      }
    }
  }
}

private struct ScoreBadge: View {
  let value: Int
  let title: String
  let color: Color

  var body: some View {
    VStack {
      Text("\(value)")
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundStyle(.primary)
      Text(title)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
    }
    .frame(width: 80, height: 68)
    .background(color.opacity(0.22))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(color.opacity(0.6), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}

private struct ResultsCard: View {
  let items: [CleanupFinding]

  var body: some View {
    MacPanel {
      VStack(alignment: .leading, spacing: 12) {
        Text("Detected cleanup findings")
          .font(.system(size: 22, weight: .semibold, design: .rounded))

        if items.isEmpty {
          Text("No cleanup findings detected in the selected folders.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        } else {
          VStack(spacing: 10) {
            ForEach(items, id: \.id) { item in
              FindingRow(item: item)
            }
          }
        }
      }
    }
  }
}

private struct FindingRow: View {
  let item: CleanupFinding

  var body: some View {
    MacPanel {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 34, height: 34)
          Image(systemName: "sparkles.rectangle.stack.fill")
            .foregroundColor(Color.accentColor)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text(item.title)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(2)

          Text("\(item.subtitle) • \(item.sourceScanner) scanner")
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)

          if let metadata = item.metadata {
            Text(metadata)
              .font(.system(size: 15, weight: .regular, design: .rounded))
              .foregroundStyle(.secondary)
          }

          Text(item.path)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(2)

          Text(item.recommendedAction)
            .font(.system(size: 16, design: .rounded))
            .foregroundStyle(.primary)

          VStack(alignment: .leading, spacing: 7) {
            Text("Safe cleanup targets")
              .font(.system(size: 12, weight: .bold, design: .rounded))
              .foregroundStyle(.secondary)

            FlowLayout {
              ForEach(item.cleanupTargets, id: \.self) { target in
                Text(target.name)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Color(nsColor: NSColor.controlBackgroundColor))
                  .clipShape(Capsule())
                  .foregroundStyle(.primary)
                  .font(.system(size: 12, design: .rounded))
              }
            }
          }

          Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
          } label: {
            Label("Reveal in Finder", systemImage: "folder")
          }
          .buttonStyle(.bordered)
          .controlSize(.regular)
        }

        Spacer()
        ConfidenceChip(confidence: item.confidenceScore, band: item.confidenceBand)
      }
    }
  }
}

private struct ConfidenceChip: View {
  let confidence: Int
  let band: CleanupConfidenceBand

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(bandColor)
        .frame(width: 10, height: 10)
      Text("\(band.rawValue.uppercased())")
        .font(.system(size: 12, weight: .semibold, design: .rounded))
      Text("\(confidence)")
        .font(.system(size: 10, weight: .bold, design: .rounded))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(bandColor.opacity(0.28))
    .clipShape(Capsule())
    .foregroundStyle(.white)
    .overlay(
      Capsule().stroke(bandColor.opacity(0.7), lineWidth: 1)
    )
  }

  private var bandColor: Color {
    switch band {
    case .high:
      return .green
    case .medium:
      return .yellow
    case .low:
      return .orange
    }
  }
}

private struct EmptyStateCard: View {
  var body: some View {
    MacPanel {
      VStack(spacing: 10) {
        Text("No scan result yet")
          .font(.system(size: 22, weight: .semibold, design: .rounded))
        Text("Choose folders and run a scan to list safe cleanup opportunities.")
          .font(.body)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 160)
      .frame(alignment: .center)
    }
  }
}

private struct FlowLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let containerWidth = proposal.width ?? 700
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var totalHeight: CGFloat = 0

    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > containerWidth && x > 0 {
        x = 0
        y += rowHeight + 8
        rowHeight = 0
      }
      x += size.width + 8
      rowHeight = max(rowHeight, size.height)
      totalHeight = max(totalHeight, y + rowHeight)
    }

    return CGSize(width: containerWidth, height: totalHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let containerWidth = bounds.width
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0

    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > containerWidth && x > 0 {
        x = 0
        y += rowHeight + 8
        rowHeight = 0
      }
      view.place(
        at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
        proposal: ProposedViewSize(width: size.width, height: size.height)
      )
      x += size.width + 8
      rowHeight = max(rowHeight, size.height)
    }
  }
}

@MainActor
final class ScanStore: ObservableObject {
  @Published var selectedRoots: [URL] = []
  @Published var minimumConfidence: String = "6"
  @Published var maxDepth: String = ""
  @Published var includeHidden: Bool = false
  @Published var followSymlinks: Bool = false
  @Published var isScanning: Bool = false
  @Published var status: String = "Ready"
  @Published var lastReport: CleanupScanReport?

  var isInputValid: Bool {
    if let value = Int(minimumConfidence.trimmingCharacters(in: .whitespacesAndNewlines)) {
      return value >= 0 && value <= 10
    }
    return false
  }

  var canScan: Bool {
    isInputValid && !selectedRoots.isEmpty
  }

  func scan() {
    guard !isScanning else { return }

    guard !selectedRoots.isEmpty else {
      status = "Select at least one folder to scan."
      return
    }

    guard isInputValid else {
      status = "Enter a valid minimum confidence."
      return
    }

    let minimumConfidenceValue = Int(minimumConfidence.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 6
    let parsedRoots = selectedRoots
      .map { $0.standardizedFileURL.path }
      .filter { !$0.isEmpty }
    let scanRoots = selectedRoots

    let parsedMaxDepth = Int(maxDepth.trimmingCharacters(in: .whitespacesAndNewlines))
    let options = CleanupScanOptions(
      roots: parsedRoots,
      minimumConfidence: minimumConfidenceValue,
      maxDepth: parsedMaxDepth.flatMap { $0 > 0 ? $0 : nil },
      skipHiddenDirectories: !includeHidden,
      followSymlinks: followSymlinks
    )

    isScanning = true
    status = "Starting scan..."
    lastReport = nil

    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      var grantedRoots: [URL] = []
      var deniedRoots: [String] = []

      for root in scanRoots {
        if root.startAccessingSecurityScopedResource() {
          grantedRoots.append(root)
        } else {
          deniedRoots.append(root.path)
        }
      }

      if !deniedRoots.isEmpty {
        let denied = deniedRoots.joined(separator: ", ")
        await MainActor.run {
          self.status = "Cannot access \(denied). Re-add folder from picker."
          self.isScanning = false
        }
        return
      }

      defer {
        for root in grantedRoots {
          root.stopAccessingSecurityScopedResource()
        }
      }

      let start = Date()
      let report = CleanupEngine().scanReport(options: options)
      let total = report.summary["total", default: 0]
      let high = report.summary["high", default: 0]
      let medium = report.summary["medium", default: 0]
      let low = report.summary["low", default: 0]
      let elapsed = Int(Date().timeIntervalSince(start) * 1000)
      await MainActor.run {
        self.lastReport = report
        self.isScanning = false
        self.status = "Completed in \(elapsed)ms. Found \(total) cleanup item(s): \(high) high, \(medium) medium, \(low) low."
      }
    }
  }

  func addScanRoots() {
    let panel = NSOpenPanel()
    panel.message = "Choose folders that Mac Cleaner can scan"
    panel.prompt = "Add"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true

    if panel.runModal() == .OK {
      let merged = selectedRoots + panel.urls.map(\.standardizedFileURL)
      var unique: [URL] = []
      var seen = Set<String>()
      for item in merged {
        let path = item.standardizedFileURL.path
        if seen.insert(path).inserted {
          unique.append(item.standardizedFileURL)
        }
      }
      selectedRoots = unique
    }
  }

  func removeSelectedRoot(_ url: URL) {
    selectedRoots.removeAll {
      $0.standardizedFileURL.path == url.standardizedFileURL.path
    }
  }

  func clearScanRoots() {
    selectedRoots = []
  }
}
