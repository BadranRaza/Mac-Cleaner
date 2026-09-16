import AppKit
import ReclaimCore
import SwiftUI

/// ReclaimCore.Category, named to avoid AppKit's `Category`.
typealias FileGroup = ReclaimCore.Category

@main
struct ReclaimApp: App {
  var body: some Scene {
    Window("Reclaim", id: "main") {
      ContentView()
        .frame(minWidth: 640, minHeight: 540)
        .tint(Brand.teal)
    }
    .defaultSize(width: 820, height: 660)
    .windowStyle(.hiddenTitleBar)
  }
}

// MARK: - Model

@MainActor @Observable
final class Model {
  enum Phase { case idle, scanning, quickReview, results, cleaning, done }

  var phase = Phase.idle
  var findings: [Finding] = []
  /// Selected item URLs; each item can be kept or removed on its own.
  var selection: Set<URL> = []
  /// The group being reviewed, or nil for the overview.
  var openGroup: FileGroup?
  var result: CleanResult?
  var hasFullDiskAccess = ReclaimCore.hasFullDiskAccess()
  /// Big things Reclaim leaves alone, explained.
  var insights: [Insight] = []
  private var scanTask: Task<Void, Never>?

  // Uninstall
  var showingUninstall = false
  var apps: [InstalledApp] = []
  var appToRemove: InstalledApp?
  var plan: [Finding]?
  var planSelection: Set<URL> = []
  var uninstallMessage: String?

  var groups: [FileGroup] { FileGroup.allCases.filter { !findings(in: $0).isEmpty } }
  var selected: [Finding] { findings.map { $0.only(selection) }.filter { !$0.targets.isEmpty } }
  var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }
  var foundBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }

  func findings(in group: FileGroup) -> [Finding] { findings.filter { $0.category == group } }
  func urls(in group: FileGroup) -> [URL] { findings(in: group).flatMap { $0.targets.map(\.url) } }

  /// Scan, then offer to clean only Safe items in one step.
  func quickClean() { scan(quick: true) }

  func goHome() {
    phase = .idle
    openGroup = nil
  }

  func selectedBytes(in group: FileGroup) -> Int64 {
    findings(in: group).flatMap(\.targets).filter { selection.contains($0.url) }.reduce(0) { $0 + $1.bytes }
  }

  func scan(quick: Bool = false) {
    phase = .scanning
    openGroup = nil
    scanTask = Task {
      async let explained = Task.detached(priority: .utility) { await Cleaner().insights() }.value
      let results = await Task.detached(priority: .userInitiated) { await Cleaner().scan() }.value
      guard !Task.isCancelled else { return }
      insights = await explained
      findings = results
      selection = Set(results.filter(\.preselected).flatMap { $0.targets.map(\.url) })
      phase = quick && !results.isEmpty ? .quickReview : .results
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

  func binding(_ url: URL) -> Binding<Bool> {
    Binding(
      get: { self.selection.contains(url) },
      set: { if $0 { self.selection.insert(url) } else { self.selection.remove(url) } }
    )
  }

  func openUninstall() {
    showingUninstall = true
    appToRemove = nil
    Task { apps = await Task.detached { Cleaner().installedApps() }.value }
  }

  func choose(_ app: InstalledApp) {
    appToRemove = app
    plan = nil
    uninstallMessage = nil
    Task {
      let found = await Task.detached(priority: .userInitiated) { await Cleaner().uninstallPlan(for: app) }.value
      guard appToRemove == app else { return }
      plan = found
      planSelection = Set(found.filter(\.preselected).flatMap { $0.targets.map(\.url) })
    }
  }

  func uninstall() {
    guard let app = appToRemove, let plan else { return }
    let chosen = plan.map { $0.only(planSelection) }.filter { !$0.targets.isEmpty }
    Task {
      let result = await Cleaner.uninstall(app, plan: chosen)
      if result.failures.isEmpty {
        uninstallMessage = "\(app.name) and its files (\(format(result.trashedBytes))) are in the Trash. Empty the Trash to free the space."
        apps.removeAll { $0 == app }
        appToRemove = nil
      } else {
        uninstallMessage = result.failures.first
      }
    }
  }

  func planBinding(_ url: URL) -> Binding<Bool> {
    Binding(
      get: { self.planSelection.contains(url) },
      set: { if $0 { self.planSelection.insert(url) } else { self.planSelection.remove(url) } }
    )
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

extension FileGroup {
  var color: Color {
    switch self {
    case .caches: .teal
    case .logs: .gray
    case .trash: .pink
    case .mail: .cyan
    case .leftovers: .purple
    case .duplicates: .mint
    case .developer: .orange
    case .xcode: .blue
    case .unity: .indigo
    case .nodeModules: .green
    case .pods: .red
    }
  }
}

extension Safety {
  var color: Color {
    switch self {
    case .safe: .green
    case .takesTime: Color(red: 0.86, green: 0.58, blue: 0.0)
    case .checkFirst: Color(red: 0.93, green: 0.33, blue: 0.20)
    }
  }

  var symbol: String {
    switch self {
    case .safe: "checkmark.circle.fill"
    case .takesTime: "clock.fill"
    case .checkFirst: "exclamationmark.triangle.fill"
    }
  }
}

struct SafetyTag: View {
  let safety: Safety

  var body: some View {
    Label(safety.title, systemImage: safety.symbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(safety.color)
      .padding(.horizontal, 8).padding(.vertical, 3)
      .background(safety.color.opacity(0.13), in: Capsule())
      .fixedSize()
      .help(safety.explanation)
  }
}

struct IconTile: View {
  let symbol: String
  let color: Color
  var size: CGFloat = 32

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.46, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
  }
}

/// The owning app's icon when we know the app, otherwise the group's tile.
struct ItemIcon: View {
  let target: Target
  let group: FileGroup

  var body: some View {
    if let id = target.appID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 30, height: 30)
    } else if group == .leftovers || group == .duplicates {
      // Real Finder icons make loose files and folders recognizable.
      Image(nsImage: NSWorkspace.shared.icon(forFile: target.url.path)).resizable().frame(width: 30, height: 30)
    } else {
      IconTile(symbol: group.symbol, color: group.color, size: 26).frame(width: 30, height: 30)
    }
  }
}

struct PrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(.white)
      .padding(.horizontal, 22).padding(.vertical, 10)
      .background(Brand.gradient, in: Capsule())
      .shadow(color: Brand.teal.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 4)
      .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.85 : 1)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .fixedSize()
  }
}

/// Round checkmark; shows a dash when a group is partly selected.
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

/// Rounded card of rows separated by hairlines.
struct Card<Item, Row: View>: View {
  let items: [Item]
  @ViewBuilder let row: (Item) -> Row

  var body: some View {
    VStack(spacing: 0) {
      ForEach(items.indices, id: \.self) { index in
        if index > 0 { Divider().padding(.leading, 56) }
        row(items[index]).padding(.horizontal, 14).padding(.vertical, 10)
      }
    }
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

// MARK: - Screens

struct ContentView: View {
  @State private var model = Model()

  var body: some View {
    Group {
      if model.showingUninstall {
        UninstallView(model: model)
      } else {
      switch model.phase {
      case .idle: HomeView(model: model)
      case .scanning, .cleaning: WorkingView(model: model)
      case .quickReview: QuickReviewView(model: model)
      case .results where model.findings.isEmpty: TidyView(model: model)
      case .results: ResultsView(model: model)
      case .done: DoneView(model: model)
      }
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
    VStack(spacing: 30) {
      if !model.hasFullDiskAccess { AccessBanner().frame(maxWidth: 640) }
      Spacer(minLength: 0)
      HStack(spacing: 40) {
        DiskRing()
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
            Text("Reclaim").font(.headline).foregroundStyle(.secondary)
          }
          Text("Let's free up\nsome space").font(.system(size: 38, weight: .bold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
          Text("Clean in one click, look through everything first,\nor remove apps you no longer use.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 14) {
        ActionCard(symbol: "sparkles", title: "Quick Clean",
                   detail: "Removes only safe files in one go. You'll see the total first.",
                   highlighted: true, action: model.quickClean)
          .keyboardShortcut(.defaultAction)
        ActionCard(symbol: "magnifyingglass", title: "Scan & Review",
                   detail: "See everything Reclaim finds and choose what goes.",
                   action: { model.scan() })
        ActionCard(symbol: "xmark.app", title: "Uninstall Apps",
                   detail: "Remove apps together with the files they leave behind.",
                   action: model.openUninstall)
      }
      .frame(maxWidth: 760)
      Spacer(minLength: 0)
      HStack(spacing: 18) {
        Label("Safe by default", systemImage: "checkmark.shield")
        Label("You decide", systemImage: "hand.tap")
        Label("Nothing hidden", systemImage: "eye")
      }
      .font(.caption).foregroundStyle(.tertiary)
    }
    .padding(32)
    .background(alignment: .top) {
      // Soft brand glow behind the hero.
      RadialGradient(colors: [Brand.teal.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 520)
        .ignoresSafeArea()
    }
  }
}

/// Ring showing how full the disk is, with free space in the middle.
struct DiskRing: View {
  @State private var shown = false
  private let volume = try? URL(fileURLWithPath: NSHomeDirectory())
    .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])

  var body: some View {
    let total = Double(max(1, volume?.volumeTotalCapacity ?? 1))
    let free = Double(volume?.volumeAvailableCapacityForImportantUsage ?? 0)
    let used = min(1, max(0, (total - free) / total))
    ZStack {
      Circle().stroke(.quaternary, lineWidth: 16)
      Circle()
        .trim(from: 0, to: shown ? used : 0)
        .stroke(Brand.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .shadow(color: Brand.teal.opacity(0.35), radius: 8)
      VStack(spacing: 2) {
        Text(format(Int64(free))).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
        Text("free of \(format(Int64(total)))").font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(width: 180, height: 180)
    .onAppear { withAnimation(.smooth(duration: 1.1)) { shown = true } }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(format(Int64(free))) free of \(format(Int64(total)))")
  }
}

/// A large, friendly choice on the home screen.
struct ActionCard: View {
  let symbol: String
  let title: String
  let detail: String
  var highlighted = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(Brand.gradient))
          .frame(width: 42, height: 42)
          .background(highlighted ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(Brand.teal.opacity(0.14)),
                      in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        Spacer(minLength: 6)
        Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
        Text(detail).font(.callout)
          .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
          .fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .padding(18)
      .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
      .background {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(highlighted ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.quaternary.opacity(0.55)))
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(.white.opacity(highlighted ? 0.25 : 0.06))
      }
      .shadow(color: (highlighted ? Brand.teal : .black).opacity(hovering ? 0.35 : 0.15), radius: hovering ? 18 : 8, y: hovering ? 8 : 3)
      .scaleEffect(hovering ? 1.02 : 1)
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.smooth(duration: 0.2), value: hovering)
  }
}

/// After a Quick Clean scan: the safe total, what it includes, and one button.
struct QuickReviewView: View {
  let model: Model

  var body: some View {
    let groups = model.groups.filter { model.selectedBytes(in: $0) > 0 }
    let needsLook = model.foundBytes - model.selectedBytes
    VStack(spacing: 20) {
      Image(systemName: "sparkles")
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 76, height: 76)
        .background(Brand.gradient, in: Circle())
        .shadow(color: Brand.teal.opacity(0.4), radius: 16, y: 6)
      if groups.isEmpty {
        Text("Nothing safe to clean right now").font(.system(size: 30, weight: .bold, design: .rounded))
      } else {
        VStack(spacing: 6) {
          Text("\(format(model.selectedBytes)) ready to clean").font(.system(size: 36, weight: .bold, design: .rounded))
          Text("Only files marked Safe. Apps make new ones by themselves when they need them.")
            .foregroundStyle(.secondary)
        }
        Card(items: groups) { group in
          HStack(spacing: 12) {
            IconTile(symbol: group.symbol, color: group.color, size: 30)
            Text(group.title)
            Spacer()
            Text(format(model.selectedBytes(in: group))).monospacedDigit().foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: 440)
      }
      if needsLook > 0 {
        Text("Another \(format(needsLook)) needs a look before it goes.").font(.callout).foregroundStyle(.secondary)
      }
      HStack(spacing: 12) {
        Button("Review First") { model.phase = .results }.controlSize(.large)
        if !groups.isEmpty {
          Button {
            model.clean()
          } label: {
            Label("Clean Now", systemImage: "sparkles")
          }
          .buttonStyle(PrimaryButton())
          .keyboardShortcut(.defaultAction)
        }
      }
      Button("Cancel", action: model.goHome).buttonStyle(.plain).foregroundStyle(.secondary)
    }
    .padding(32)
  }
}

struct AccessBanner: View {
  var body: some View {
    HStack(spacing: 12) {
      IconTile(symbol: "lock.open.fill", color: .orange, size: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text("Allow Full Disk Access to find more").font(.callout.weight(.semibold))
        Text("Lets Reclaim check your Trash, email attachments and projects in Documents.")
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
      Text(model.phase == .cleaning ? "Cleaning up…" : "Looking around your Mac…").font(.title2.weight(.semibold))
      if model.phase == .scanning { Button("Cancel", action: model.cancelScan).controlSize(.large) }
    }
  }
}

struct TidyView: View {
  let model: Model

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "sparkles").font(.system(size: 56)).foregroundStyle(Brand.gradient)
      Text("Your Mac is already tidy").font(.title.bold())
      Text("Nothing worth cleaning right now.").foregroundStyle(.secondary)
      Button("Back to Home", action: model.goHome).buttonStyle(PrimaryButton())
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
      HStack(spacing: 12) {
        Button("Scan Again") { model.scan() }.controlSize(.large)
        Button("Done", action: model.goHome)
          .buttonStyle(PrimaryButton())
          .keyboardShortcut(.defaultAction)
      }
      .padding(.top, 8)
    }
  }
}

// MARK: - Results

struct ResultsView: View {
  @Bindable var model: Model
  @State private var confirming = false

  var body: some View {
    ScrollView {
      Group {
        if let group = model.openGroup { GroupDetail(model: model, group: group) } else { overview }
      }
      .padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 20)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .id(model.openGroup)
    .safeAreaInset(edge: .bottom) { actionBar }
  }

  private var overview: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(format(model.foundBytes)) found").font(.system(size: 32, weight: .bold, design: .rounded))
          Text("Only safe items are selected. Open a group to see what's inside.").foregroundStyle(.secondary)
        }
        Spacer()
        Button("Uninstall Apps", action: model.openUninstall)
        Button("Scan Again") { model.scan() }
      }
      if !model.hasFullDiskAccess { AccessBanner() }
      Card(items: model.groups) { GroupRow(model: model, group: $0) }
      if !model.insights.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Also taking space").font(.headline)
          Text("Reclaim leaves these alone. Here's what they are, and how to shrink them yourself.")
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        Card(items: model.insights) { InsightRow(insight: $0) }
      }
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Safety.allCases, id: \.self) { safety in
          HStack(spacing: 8) {
            SafetyTag(safety: safety).frame(width: 110, alignment: .leading)
            Text(safety.explanation).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      .padding(.leading, 4)
    }
  }

  private var actionBar: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(format(model.selectedBytes)) selected").font(.title3.bold()).monospacedDigit()
          .contentTransition(.numericText())
        Text("\(model.selection.count) item\(model.selection.count == 1 ? "" : "s")")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        confirming = true
      } label: {
        Label("Clean", systemImage: "sparkles")
      }
      .buttonStyle(PrimaryButton())
      .disabled(model.selection.isEmpty)
      .keyboardShortcut(.defaultAction)
      .confirmationDialog("Clean \(format(model.selectedBytes))?", isPresented: $confirming) {
        Button("Clean", role: .destructive, action: model.clean)
      } message: {
        Text(confirmMessage)
      }
    }
    .padding(.horizontal, 28).padding(.vertical, 14)
    .background(.bar)
    .animation(.smooth, value: model.selectedBytes)
  }

  private var confirmMessage: String {
    let toTrash = model.selected.filter(\.movesToTrash).reduce(Int64(0)) { $0 + $1.bytes }
    var message = toTrash > 0
      ? "\(format(toTrash)) goes to the Trash. Everything else is removed for good."
      : "Removed items can't be restored."
    if model.selected.contains(where: { $0.safety == .checkFirst }) {
      message += " Your selection includes items marked Check first."
    }
    return message
  }
}

struct GroupRow: View {
  let model: Model
  let group: FileGroup

  var body: some View {
    let findings = model.findings(in: group)
    HStack(spacing: 12) {
      Toggle(sources: model.urls(in: group).map(model.binding), isOn: \.self) {
        IconTile(symbol: group.symbol, color: group.color)
      }
      .toggleStyle(CheckCircle())
      .accessibilityLabel(group.title)
      Button {
        withAnimation(.smooth) { model.openGroup = group }
      } label: {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(group.title).font(.headline)
            Text(group.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer(minLength: 8)
          ForEach(Set(findings.map(\.safety)).sorted(), id: \.self) { SafetyTag(safety: $0) }
          Text(format(findings.reduce(0) { $0 + $1.bytes })).monospacedDigit().frame(minWidth: 64, alignment: .trailing)
          Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }
}

struct GroupDetail: View {
  @Bindable var model: Model
  let group: FileGroup

  var body: some View {
    let urls = model.urls(in: group)
    let allSelected = urls.allSatisfy(model.selection.contains)
    VStack(alignment: .leading, spacing: 18) {
      Button {
        withAnimation(.smooth) { model.openGroup = nil }
      } label: {
        Label("All groups", systemImage: "chevron.left").font(.callout.weight(.medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(Brand.teal)
      .keyboardShortcut(.cancelAction)

      HStack(alignment: .top, spacing: 14) {
        IconTile(symbol: group.symbol, color: group.color, size: 48)
        VStack(alignment: .leading, spacing: 4) {
          Text(group.title).font(.system(size: 26, weight: .bold, design: .rounded))
          Text(group.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Button(allSelected ? "Select None" : "Select All") {
          if allSelected { model.selection.subtract(urls) } else { model.selection.formUnion(urls) }
        }
      }

      ForEach(model.findings(in: group)) { finding in
        if finding.targets.count == 1 {
          Card(items: finding.targets) { ItemRow(isOn: model.binding($0.url), target: $0, group: group, finding: finding, showTag: true) }
        } else {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Text(finding.title).font(.headline)
              SafetyTag(safety: finding.safety)
              if finding.movesToTrash { Text("Moves to Trash").font(.caption).foregroundStyle(.secondary) }
              Spacer()
              Text(format(finding.bytes)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Card(items: finding.targets) { ItemRow(isOn: model.binding($0.url), target: $0, group: group, finding: finding, showTag: false) }
          }
        }
      }
    }
  }
}

struct ItemRow: View {
  @Binding var isOn: Bool
  let target: Target
  let group: FileGroup
  let finding: Finding
  let showTag: Bool

  var body: some View {
    HStack(spacing: 10) {
      Toggle(isOn: $isOn) {
        HStack(spacing: 10) {
          ItemIcon(target: target, group: group)
          VStack(alignment: .leading, spacing: 1) {
            Text(target.name).lineLimit(1)
            if showTag && finding.movesToTrash {
              Text("Moves to Trash").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      .toggleStyle(CheckCircle())
      Spacer(minLength: 8)
      if showTag { SafetyTag(safety: finding.safety) }
      Text(format(target.bytes)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 64, alignment: .trailing)
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([target.url])
      } label: {
        Image(systemName: "folder")
      }
      .buttonStyle(.borderless)
      .help("Show in Finder")
    }
    .help((target.url.path as NSString).abbreviatingWithTildeInPath)
  }
}

struct InsightRow: View {
  let insight: Insight

  var body: some View {
    HStack(spacing: 12) {
      IconTile(symbol: "info", color: .gray, size: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(insight.title)
        Text(insight.advice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Text(insight.bytes.map(format) ?? "Large").monospacedDigit().foregroundStyle(.secondary)
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([insight.url])
      } label: {
        Image(systemName: "folder")
      }
      .buttonStyle(.borderless)
      .help("Show in Finder")
    }
  }
}

// MARK: - Uninstall

struct UninstallView: View {
  @Bindable var model: Model
  @State private var search = ""
  @State private var confirming = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Button {
          withAnimation(.smooth) {
            if model.appToRemove != nil { model.appToRemove = nil } else { model.showingUninstall = false }
          }
        } label: {
          Label(model.appToRemove == nil ? "Back" : "All apps", systemImage: "chevron.left").font(.callout.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.teal)
        .keyboardShortcut(.cancelAction)

        if let message = model.uninstallMessage {
          Label(message, systemImage: "checkmark.circle.fill")
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if let app = model.appToRemove { planView(app) } else { appList }
      }
      .padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 20)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .safeAreaInset(edge: .bottom) {
      if let app = model.appToRemove, model.plan != nil { actionBar(app) }
    }
  }

  private var appList: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Uninstall Apps").font(.system(size: 32, weight: .bold, design: .rounded))
        Text("Removes an app and the files it left on your Mac. Everything goes to the Trash first.")
          .foregroundStyle(.secondary)
      }
      TextField("Search apps", text: $search).textFieldStyle(.roundedBorder).controlSize(.large)
      let apps = model.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
      if model.apps.isEmpty {
        ProgressView().frame(maxWidth: .infinity)
      } else {
        Card(items: apps) { app in
          Button {
            withAnimation(.smooth) { model.choose(app) }
          } label: {
            HStack(spacing: 12) {
              Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 32, height: 32)
              VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(app.lastUsed.map { "Last opened \($0.formatted(.relative(presentation: .named)))" } ?? "Never opened")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func planView(_ app: InstalledApp) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 56, height: 56)
        VStack(alignment: .leading, spacing: 4) {
          Text(app.name).font(.system(size: 26, weight: .bold, design: .rounded))
          Text("The app and the files it created. Anything marked Check first only matches by name.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      if let plan = model.plan {
        ForEach(plan) { finding in
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Text(finding.title).font(.headline)
              SafetyTag(safety: finding.safety)
              Spacer()
              Text(format(finding.bytes)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Card(items: finding.targets) {
              ItemRow(isOn: model.planBinding($0.url), target: $0, group: .leftovers, finding: finding, showTag: false)
            }
          }
        }
      } else {
        HStack { ProgressView(); Text("Finding its files…").foregroundStyle(.secondary) }
      }
    }
  }

  private func actionBar(_ app: InstalledApp) -> some View {
    let bytes = (model.plan ?? []).flatMap(\.targets).filter { model.planSelection.contains($0.url) }.reduce(Int64(0)) { $0 + $1.bytes }
    return HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(format(bytes)) selected").font(.title3.bold()).monospacedDigit()
        Text("\(model.planSelection.count) item\(model.planSelection.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        confirming = true
      } label: {
        Label("Uninstall", systemImage: "trash")
      }
      .buttonStyle(PrimaryButton())
      .disabled(model.planSelection.isEmpty)
      .keyboardShortcut(.defaultAction)
      .confirmationDialog("Uninstall \(app.name)?", isPresented: $confirming) {
        Button("Move to Trash", role: .destructive, action: model.uninstall)
      } message: {
        Text("\(app.name) will quit, and the selected items move to the Trash. You can put them back from the Trash.")
      }
    }
    .padding(.horizontal, 28).padding(.vertical, 14)
    .background(.bar)
  }
}
