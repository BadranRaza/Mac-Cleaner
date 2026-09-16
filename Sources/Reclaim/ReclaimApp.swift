import AppKit
import ReclaimCore
import SwiftUI

@main
struct ReclaimApp: App {
  var body: some Scene {
    Window("Reclaim", id: "main") {
      ContentView()
        .frame(minWidth: 560, minHeight: 440)
    }
    .defaultSize(width: 760, height: 600)
    .windowToolbarStyle(.unifiedCompact)
  }
}

@MainActor @Observable
final class Model {
  enum Phase { case idle, scanning, results, cleaning }

  var phase = Phase.idle
  var findings: [Finding] = []
  var selection: Set<String> = []
  var hasFullDiskAccess = ReclaimCore.hasFullDiskAccess()
  var message: String?
  private var scanTask: Task<Void, Never>?

  var selected: [Finding] { findings.filter { selection.contains($0.id) } }
  var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }

  func scan() {
    phase = .scanning
    scanTask = Task {
      let results = await Task.detached(priority: .userInitiated) { await Cleaner().scan() }.value
      guard !Task.isCancelled else { return }
      findings = results
      selection = Set(results.filter(\.preselected).map(\.id))
      phase = .results
    }
  }

  func cancelScan() {
    scanTask?.cancel()
    phase = findings.isEmpty ? .idle : .results
  }

  func clean() {
    let chosen = selected
    phase = .cleaning
    Task {
      let result = await Task.detached(priority: .userInitiated) { Cleaner.clean(chosen) }.value
      var parts = ["Freed \(format(result.freedBytes))."]
      if result.trashedBytes > 0 { parts.append("\(format(result.trashedBytes)) moved to the Trash.") }
      if !result.failures.isEmpty { parts.append("\(result.failures.count) item(s) couldn't be removed.") }
      message = parts.joined(separator: " ")
      scan()
    }
  }
}

func format(_ bytes: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct ContentView: View {
  @State private var model = Model()
  @State private var confirming = false

  var body: some View {
    VStack(spacing: 0) {
      if !model.hasFullDiskAccess { AccessBanner() }
      switch model.phase {
      case .idle: EmptyState(scan: model.scan)
      case .scanning, .cleaning: Busy(model: model)
      case .results: ResultsList(model: model)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if model.phase == .results { bottomBar }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      model.hasFullDiskAccess = hasFullDiskAccess()
    }
    .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { _ in model.message = nil })) {}
  }

  private var bottomBar: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(format(model.selectedBytes)).font(.title2.bold()).monospacedDigit()
          .contentTransition(.numericText())
        Text("\(model.selection.count) of \(model.findings.count) selected").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Scan Again", action: model.scan)
      Button("Clean") { confirming = true }
        .buttonStyle(.borderedProminent)
        .disabled(model.selection.isEmpty)
        .keyboardShortcut(.defaultAction)
        .confirmationDialog("Clean \(format(model.selectedBytes))?", isPresented: $confirming) {
          Button("Clean", role: .destructive, action: model.clean)
        } message: {
          Text("Caches and logs are deleted permanently. Archives and Mail attachments go to the Trash.")
        }
    }
    .controlSize(.large)
    .padding()
    .background(.bar)
    .animation(.default, value: model.selectedBytes)
  }
}

struct EmptyState: View {
  let scan: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
      Text("Reclaim").font(.largeTitle.bold())
      Text("Find caches, logs and build leftovers you can safely remove.")
        .foregroundStyle(.secondary)
      Button("Scan", action: scan)
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        .keyboardShortcut(.defaultAction)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct Busy: View {
  let model: Model

  var body: some View {
    VStack(spacing: 14) {
      ProgressView().controlSize(.large)
      Text(model.phase == .cleaning ? "Cleaning…" : "Scanning…").foregroundStyle(.secondary)
      if model.phase == .scanning { Button("Cancel", action: model.cancelScan) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct AccessBanner: View {
  var body: some View {
    HStack {
      Image(systemName: "lock.shield").foregroundStyle(.orange)
      Text("Grant Full Disk Access to also scan Trash, Mail, app containers and projects in Desktop, Documents and Downloads.").font(.callout)
      Spacer()
      Button("Open Settings") {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
      }
    }
    .padding(.horizontal).padding(.vertical, 8)
    .background(.orange.opacity(0.12))
  }
}

struct ResultsList: View {
  @Bindable var model: Model

  var body: some View {
    if model.findings.isEmpty {
      ContentUnavailableView("Nothing to clean", systemImage: "checkmark.circle", description: Text("Your Mac is tidy."))
    } else {
      List {
        ForEach(Category.allCases, id: \.self) { category in
          let items = model.findings.filter { $0.category == category }
          if !items.isEmpty {
            Section {
              ForEach(items) { FindingRow(finding: $0, selection: $model.selection) }
            } header: {
              HStack {
                Label(category.title, systemImage: category.symbol)
                Spacer()
                Text(format(items.reduce(0) { $0 + $1.bytes })).monospacedDigit()
              }
            }
          }
        }
      }
      .listStyle(.inset(alternatesRowBackgrounds: false))
    }
  }
}

struct FindingRow: View {
  let finding: Finding
  @Binding var selection: Set<String>
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      toggle
      if finding.targets.count > 1 { breakdown }
    }
    .padding(.vertical, 3)
    .contextMenu {
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.location]) }
    }
  }

  private var toggle: some View {
    Toggle(isOn: Binding(
      get: { selection.contains(finding.id) },
      set: { if $0 { selection.insert(finding.id) } else { selection.remove(finding.id) } }
    )) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(finding.title)
            if finding.movesToTrash {
              Text("Moves to Trash").font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            }
          }
          Text((finding.location.path as NSString).abbreviatingWithTildeInPath)
            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        Spacer()
        Text(format(finding.bytes)).monospacedDigit().foregroundStyle(.secondary)
      }
    }
    .toggleStyle(.checkbox)
  }

  private var breakdown: some View {
    VStack(alignment: .leading, spacing: 3) {
      Button {
        withAnimation(.snappy) { expanded.toggle() }
      } label: {
        Label("\(finding.targets.count) items", systemImage: "chevron.right")
          .labelStyle(TrailingIcon(rotated: expanded))
      }
      .buttonStyle(.plain)
      if expanded {
        ForEach(finding.targets.sorted { $0.bytes > $1.bytes }.prefix(25), id: \.url) { target in
          HStack {
            Text(target.url.lastPathComponent).lineLimit(1)
            Spacer()
            Text(format(target.bytes)).monospacedDigit()
          }
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.leading, 20)
  }
}

private struct TrailingIcon: LabelStyle {
  let rotated: Bool

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.title
      configuration.icon.imageScale(.small).rotationEffect(.degrees(rotated ? 90 : 0))
    }
  }
}
