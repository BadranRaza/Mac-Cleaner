import AppKit
import ReclaimCore
import SwiftUI

@main
struct ReclaimApp: App {
  var body: some Scene {
    Window("Reclaim", id: "main") {
      ContentView()
        .frame(minWidth: 820, minHeight: 560)
        .tint(Brand.teal)
    }
    .defaultSize(width: 980, height: 680)
    .windowStyle(.hiddenTitleBar)
  }
}

// MARK: - Model

@MainActor @Observable
final class Model {
  enum Phase { case idle, scanning, results, cleaning, done }

  var phase = Phase.idle
  var findings: [Finding] = []
  /// Selected target URLs; each item can be kept or removed on its own.
  var selection: Set<URL> = []
  var category: ReclaimCore.Category?
  var result: CleanResult?
  var hasFullDiskAccess = ReclaimCore.hasFullDiskAccess()
  private var scanTask: Task<Void, Never>?

  var categories: [ReclaimCore.Category] { ReclaimCore.Category.allCases.filter { !items(in: $0).isEmpty } }
  var selected: [Finding] { findings.map { $0.only(selection) }.filter { !$0.targets.isEmpty } }
  var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }
  var foundBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }

  func items(in category: ReclaimCore.Category) -> [Finding] { findings.filter { $0.category == category } }
  func urls(in category: ReclaimCore.Category) -> [URL] { items(in: category).flatMap { $0.targets.map(\.url) } }
  func bytes(in category: ReclaimCore.Category) -> Int64 { items(in: category).reduce(0) { $0 + $1.bytes } }

  func scan() {
    phase = .scanning
    scanTask = Task {
      let results = await Task.detached(priority: .userInitiated) { await Cleaner().scan() }.value
      guard !Task.isCancelled else { return }
      findings = results
      selection = Set(results.filter(\.preselected).flatMap { $0.targets.map(\.url) })
      if category.map({ !categories.contains($0) }) ?? true { category = categories.first }
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
      result = await Task.detached(priority: .userInitiated) { Cleaner.clean(chosen) }.value
      phase = .done
    }
  }
}

func format(_ bytes: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - Style

enum Brand {
  static let teal = Color(red: 0.07, green: 0.66, blue: 0.58)
  static let gradient = LinearGradient(
    colors: [Color(red: 0.20, green: 0.82, blue: 0.62), Color(red: 0.05, green: 0.47, blue: 0.64)],
    startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension ReclaimCore.Category {
  var color: Color {
    switch self {
    case .xcode: .blue
    case .unity: .indigo
    case .nodeModules: .green
    case .pods: .red
    case .developer: .orange
    case .caches: .teal
    case .logs: .gray
    case .trash: .pink
    case .mail: .cyan
    }
  }
}

struct IconTile: View {
  let symbol: String
  let color: Color
  var size: CGFloat = 32

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.48, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
  }
}

struct PrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(.white)
      .padding(.horizontal, 22).padding(.vertical, 11)
      .background(Brand.gradient, in: Capsule())
      .shadow(color: Brand.teal.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 4)
      .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.85 : 1)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
  }
}

/// Round checkmark used for all selections; shows a dash when partly selected.
struct CheckCircle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button { configuration.isOn.toggle() } label: {
      HStack(spacing: 12) {
        Image(systemName: configuration.isMixed ? "minus.circle.fill" : configuration.isOn ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(configuration.isOn || configuration.isMixed ? Brand.teal : Color.secondary.opacity(0.5))
          .contentTransition(.symbolEffect(.replace))
        configuration.label
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityValue(configuration.isMixed ? "Partly selected" : configuration.isOn ? "Selected" : "Not selected")
  }
}

// MARK: - Screens

struct ContentView: View {
  @State private var model = Model()

  var body: some View {
    Group {
      switch model.phase {
      case .idle: HomeView(model: model)
      case .scanning, .cleaning: WorkingView(model: model)
      case .results: ResultsView(model: model)
      case .done: DoneView(model: model)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .animation(.smooth, value: model.phase)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      model.hasFullDiskAccess = hasFullDiskAccess()
    }
  }
}

struct HomeView: View {
  let model: Model

  var body: some View {
    VStack(spacing: 26) {
      if !model.hasFullDiskAccess { AccessBanner().frame(maxWidth: 560) }
      Spacer()
      Image(nsImage: NSApp.applicationIconImage)
        .resizable().frame(width: 128, height: 128)
        .shadow(color: Brand.teal.opacity(0.4), radius: 30, y: 10)
      VStack(spacing: 8) {
        Text("Let's free up some space").font(.system(size: 34, weight: .bold, design: .rounded))
        Text("Reclaim finds caches, logs and leftovers from your projects.\nYou see everything first and decide what goes.")
          .multilineTextAlignment(.center).foregroundStyle(.secondary)
      }
      DiskCard().frame(maxWidth: 420)
      Button("Start Scan", action: model.scan)
        .buttonStyle(PrimaryButton())
        .keyboardShortcut(.defaultAction)
      HStack(spacing: 18) {
        Label("Safe by default", systemImage: "checkmark.shield")
        Label("You choose", systemImage: "hand.tap")
        Label("Nothing hidden", systemImage: "eye")
      }
      .font(.callout).foregroundStyle(.secondary)
      Spacer()
    }
    .padding(32)
  }
}

struct DiskCard: View {
  var reclaimable: Int64 = 0
  private let volume = try? URL(fileURLWithPath: NSHomeDirectory())
    .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])

  var body: some View {
    let total = Double(max(1, volume?.volumeTotalCapacity ?? 1))
    let free = Double(volume?.volumeAvailableCapacityForImportantUsage ?? 0)
    let used = max(0, total - free)
    let freed = min(Double(reclaimable), used)
    VStack(alignment: .leading, spacing: 8) {
      Label("Macintosh HD", systemImage: "internaldrive").font(.callout.weight(.semibold))
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(.quaternary)
          Capsule().fill(Color.secondary.opacity(0.45)).frame(width: geo.size.width * used / total)
          if reclaimable > 0 {
            Capsule().fill(Brand.gradient)
              .frame(width: max(6, geo.size.width * freed / total))
              .offset(x: geo.size.width * (used - freed) / total)
          }
        }
      }
      .frame(height: 8)
      Text(reclaimable > 0 ? "\(format(Int64(free))) free · +\(format(reclaimable)) after cleaning"
                           : "\(format(Int64(free))) free of \(format(Int64(total)))")
        .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        .contentTransition(.numericText())
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct AccessBanner: View {
  var body: some View {
    HStack(spacing: 12) {
      IconTile(symbol: "lock.open.fill", color: .orange, size: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text("See everything with Full Disk Access").font(.callout.weight(.semibold))
        Text("Adds Trash, Mail, app containers and projects in Desktop, Documents and Downloads.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      Button("Allow…") {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
      }
    }
    .padding(12)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

struct WorkingView: View {
  let model: Model
  @State private var spin = false

  var body: some View {
    VStack(spacing: 20) {
      ZStack {
        Circle().stroke(.quaternary, lineWidth: 6)
        Circle().trim(from: 0, to: 0.28)
          .stroke(Brand.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
          .rotationEffect(.degrees(spin ? 360 : 0))
          .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
      }
      .frame(width: 120, height: 120)
      .onAppear { spin = true }
      Text(model.phase == .cleaning ? "Cleaning up…" : "Looking around your Mac…")
        .font(.title2.weight(.semibold))
      Text(model.phase == .cleaning ? "Removing the items you picked." : "Checking caches, logs, Xcode, Unity and project folders.")
        .foregroundStyle(.secondary)
      if model.phase == .scanning { Button("Cancel", action: model.cancelScan).controlSize(.large) }
    }
  }
}

struct DoneView: View {
  let model: Model

  var body: some View {
    let result = model.result ?? CleanResult()
    VStack(spacing: 16) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 72))
        .foregroundStyle(Brand.gradient)
        .symbolEffect(.bounce, value: model.phase)
      Text("\(format(result.freedBytes)) freed").font(.system(size: 40, weight: .bold, design: .rounded))
      if result.trashedBytes > 0 {
        Text("\(format(result.trashedBytes)) moved to the Trash, so you can still get it back.").foregroundStyle(.secondary)
      }
      if !result.failures.isEmpty {
        Text("\(result.failures.count) item(s) couldn't be removed; they may be in use.")
          .foregroundStyle(.secondary)
          .help(result.failures.joined(separator: "\n"))
      }
      Button("Done", action: model.scan)
        .buttonStyle(PrimaryButton())
        .keyboardShortcut(.defaultAction)
        .padding(.top, 8)
    }
  }
}

// MARK: - Results

struct ResultsView: View {
  @Bindable var model: Model
  @State private var confirming = false

  var body: some View {
    if model.findings.isEmpty {
      VStack(spacing: 14) {
        Image(systemName: "sparkles").font(.system(size: 56)).foregroundStyle(Brand.gradient)
        Text("Your Mac is already tidy").font(.title.bold())
        Text("Nothing worth cleaning right now.").foregroundStyle(.secondary)
        Button("Scan Again", action: model.scan).buttonStyle(PrimaryButton())
      }
    } else {
      HStack(spacing: 0) {
        sidebar
        Divider()
        VStack(spacing: 0) {
          if let category = model.category { CategoryDetail(model: model, category: category) }
          actionBar
        }
      }
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Found").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        Text(format(model.foundBytes)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
      }
      .padding(.top, 34)
      .padding(.horizontal, 8)
      if !model.hasFullDiskAccess { AccessBanner().controlSize(.small) }
      ScrollView {
        VStack(spacing: 4) {
          ForEach(model.categories, id: \.self) { CategoryButton(model: model, category: $0) }
        }
      }
      DiskCard(reclaimable: model.selectedBytes).padding(.bottom, 14)
    }
    .padding(.horizontal, 12)
    .frame(width: 290)
    .background(.quaternary.opacity(0.35))
  }

  private var actionBar: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(format(model.selectedBytes)) selected").font(.title3.bold()).monospacedDigit()
          .contentTransition(.numericText())
        Text("\(model.selection.count) of \(model.findings.reduce(0) { $0 + $1.targets.count }) items")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Scan Again", action: model.scan).controlSize(.large).fixedSize()
      Button {
        confirming = true
      } label: {
        Label("Clean", systemImage: "sparkles").fixedSize()
      }
      .buttonStyle(PrimaryButton())
      .disabled(model.selection.isEmpty)
      .keyboardShortcut(.defaultAction)
      .confirmationDialog("Clean \(format(model.selectedBytes))?", isPresented: $confirming) {
        Button("Clean", role: .destructive, action: model.clean)
      } message: {
        Text("Items are deleted permanently, except Xcode Archives, Unity builds and Mail attachments, which go to the Trash.")
      }
    }
    .padding(16)
    .background(.bar)
    .animation(.smooth, value: model.selectedBytes)
  }
}

struct CategoryButton: View {
  let model: Model
  let category: ReclaimCore.Category

  var body: some View {
    let urls = model.urls(in: category)
    let picked = urls.filter(model.selection.contains).count
    Button {
      model.category = category
    } label: {
      HStack(spacing: 10) {
        IconTile(symbol: category.symbol, color: category.color)
        VStack(alignment: .leading, spacing: 1) {
          Text(category.title).fontWeight(.medium)
          Text(picked == 0 ? "\(urls.count) item\(urls.count == 1 ? "" : "s")" : "\(picked) of \(urls.count) selected")
            .font(.caption).foregroundStyle(picked == 0 ? Color.secondary : Brand.teal)
        }
        Spacer()
        Text(format(model.bytes(in: category))).font(.callout).monospacedDigit().foregroundStyle(.secondary)
      }
      .padding(8)
      .background(model.category == category ? Brand.teal.opacity(0.16) : .clear,
                  in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct CategoryDetail: View {
  @Bindable var model: Model
  let category: ReclaimCore.Category

  var body: some View {
    let urls = model.urls(in: category)
    let allSelected = urls.allSatisfy(model.selection.contains)
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top, spacing: 14) {
          IconTile(symbol: category.symbol, color: category.color, size: 52)
          VStack(alignment: .leading, spacing: 4) {
            Text(category.title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(category.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          Button(allSelected ? "Select None" : "Select All") {
            if allSelected { model.selection.subtract(urls) } else { model.selection.formUnion(urls) }
          }
        }
        .padding(.bottom, 6)
        ForEach(model.items(in: category)) { FindingCard(finding: $0, selection: $model.selection) }
      }
      .padding(24)
      .padding(.top, 14)
    }
    .id(category)
  }
}

struct FindingCard: View {
  let finding: Finding
  @Binding var selection: Set<URL>
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(sources: finding.targets.map(binding), isOn: \.self) {
        line(title: finding.title, url: finding.targets.count == 1 ? finding.targets[0].url : finding.location,
             bytes: finding.bytes, trash: finding.movesToTrash, prominent: true)
      }
      if finding.targets.count > 1 {
        Button {
          withAnimation(.snappy) { expanded.toggle() }
        } label: {
          HStack(spacing: 4) {
            Text(expanded ? "Hide items" : "Choose from \(finding.targets.count) items")
            Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
          }
          .font(.caption.weight(.medium)).foregroundStyle(Brand.teal)
        }
        .buttonStyle(.plain)
        .padding(.leading, 38)
        if expanded {
          VStack(spacing: 8) {
            ForEach(finding.targets.sorted { $0.bytes > $1.bytes }, id: \.url) { target in
              Toggle(isOn: binding(target)) {
                line(title: target.url.lastPathComponent, url: target.url, bytes: target.bytes, trash: false, prominent: false)
              }
            }
          }
          .padding(.leading, 38)
        }
      }
    }
    .toggleStyle(CheckCircle())
    .padding(14)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func binding(_ target: Target) -> Binding<Bool> {
    Binding(
      get: { selection.contains(target.url) },
      set: { if $0 { selection.insert(target.url) } else { selection.remove(target.url) } }
    )
  }

  private func line(title: String, url: URL, bytes: Int64, trash: Bool, prominent: Bool) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(title).font(prominent ? .headline : .callout).lineLimit(1)
          if trash {
            Label("Moves to Trash", systemImage: "arrow.uturn.backward")
              .font(.caption2.weight(.medium)).foregroundStyle(.orange)
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(.orange.opacity(0.12), in: Capsule())
          }
        }
        Text((url.path as NSString).abbreviatingWithTildeInPath)
          .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
      }
      Spacer()
      Text(format(bytes)).font(prominent ? .headline : .callout).monospacedDigit()
        .foregroundStyle(prominent ? .primary : .secondary)
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } label: {
        Image(systemName: "folder")
      }
      .buttonStyle(.borderless)
      .help("Show in Finder")
    }
  }
}
