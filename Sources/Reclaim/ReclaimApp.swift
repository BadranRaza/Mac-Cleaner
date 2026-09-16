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
  /// Space freed since the app opened, and moved to the Trash (freed once the Trash is emptied).
  var sessionFreed: Int64 = 0
  /// Free space when the app opened, for the "where you started" view on the ring.
  let startFree = Disk.now().free
  var sessionTrashed: Int64 = 0
  /// Freed across all sessions.
  var lifetimeFreed = Int64(UserDefaults.standard.integer(forKey: "lifetimeFreed"))

  func record(_ result: CleanResult) {
    sessionFreed += result.freedBytes
    sessionTrashed += result.trashedBytes
    lifetimeFreed += result.freedBytes
    UserDefaults.standard.set(Int(lifetimeFreed), forKey: "lifetimeFreed")
  }
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
  var uninstallMessage: (text: String, ok: Bool)?

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

  /// When the current findings were measured; recent results are reused instead of scanning again.
  var scannedAt: Date?
  private var estimateTask: Task<Void, Never>?
  var isEstimating: Bool { estimateTask != nil }
  var safeBytes: Int64 { findings.filter(\.preselected).reduce(0) { $0 + $1.bytes } }

  /// Read-only background scan for the home screen, so it can show what can be reclaimed.
  func estimate() {
    guard estimateTask == nil, phase == .idle, !isFresh else { return }
    estimateTask = Task {
      await measure()
      estimateTask = nil
    }
  }

  private var isFresh: Bool { scannedAt.map { Date().timeIntervalSince($0) < 120 } ?? false }

  private func measure() async {
    async let explained = Task.detached(priority: .utility) { await Cleaner().insights() }.value
    async let installed = Task.detached(priority: .utility) { Cleaner().installedApps() }.value
    let results = await Task.detached(priority: .userInitiated) { await Cleaner().scan() }.value
    guard !Task.isCancelled else { return }
    insights = await explained
    apps = await installed
    findings = results
    selection = Set(results.filter(\.preselected).flatMap { $0.targets.map(\.url) })
    scannedAt = Date()
  }

  func scan(quick: Bool = false, force: Bool = false) {
    openGroup = nil
    let next: () -> Phase = { quick && !self.findings.isEmpty ? .quickReview : .results }
    if !force, isFresh, estimateTask == nil {
      selection = Set(findings.filter(\.preselected).flatMap { $0.targets.map(\.url) })
      phase = next()
      return
    }
    phase = .scanning
    scanTask = Task {
      // Reuse a background scan that is already running.
      if let running = estimateTask, !force { await running.value } else { await measure() }
      guard !Task.isCancelled else { return }
      phase = next()
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
      let firstPass = await Task.detached(priority: .userInitiated) { Cleaner.clean(chosen) }.value
      let cleaned = Cleaner.withPassword(firstPass, plan: chosen)
      result = cleaned
      record(cleaned)
      scannedAt = nil  // what's on disk changed
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
      record(result)
      scannedAt = nil
      if result.failures.isEmpty {
        uninstallMessage = ("\(app.name) and its files (\(format(result.trashedBytes))) are in the Trash. Empty the Trash to free the space.", true)
        apps.removeAll { $0 == app }
        appToRemove = nil
      } else if result.passwordDeclined {
        uninstallMessage = ("\(app.name) wasn't removed. It was installed for everyone on this Mac, so macOS needs your password.", false)
      } else {
        uninstallMessage = ("Some of \(app.name)'s items couldn't be moved to the Trash. They may be in use; quit apps that use them and try again.", false)
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

enum Layout {
  /// Widest a list gets; beyond this, lines become hard to follow on big screens.
  static let readable: CGFloat = 960
}

struct HomeView: View {
  let model: Model

  var body: some View {
    // Designed for the default window; on bigger windows (full screen) everything grows together.
    GeometryReader { geo in
      let scale = min(1.5, max(1, min(geo.size.width / 880, geo.size.height / 700)))
      content
        .frame(width: geo.size.width / scale, height: geo.size.height / scale)
        .scaleEffect(scale)
        .frame(width: geo.size.width, height: geo.size.height)
    }
    .task { model.estimate() }
    .background {
      // Soft brand glow across the whole window.
      GeometryReader { geo in
        RadialGradient(colors: [Brand.teal.opacity(0.22), .clear], center: .top, startRadius: 0,
                       endRadius: max(geo.size.width, geo.size.height) * 0.7)
      }
      .ignoresSafeArea()
    }
  }

  private var content: some View {
    VStack(spacing: 30) {
      if !model.hasFullDiskAccess { AccessBanner().frame(maxWidth: 640) }
      Spacer(minLength: 0)
      HStack(spacing: 40) {
        DiskRing(disk: Disk.now(), startFree: model.startFree, reclaimed: model.sessionFreed,
                 safe: model.scannedAt == nil ? nil : model.safeBytes,
                 more: model.foundBytes - model.safeBytes, checking: model.isEstimating)
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
            Text("Reclaim").font(.headline).foregroundStyle(.secondary)
          }
          Text("Let's free up\nsome space").font(.system(size: 38, weight: .bold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
          Text("Clean in one click, look through everything first,\nor remove apps you no longer use.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          if model.sessionFreed + model.sessionTrashed > 0 || model.lifetimeFreed > 0 {
            SessionBadge(model: model).padding(.top, 4)
          }
        }
      }
      let ready = model.scannedAt != nil
      HStack(spacing: 14) {
        ActionCard(symbol: "sparkles", title: "Quick Clean", detail: "Only safe files, in one step.",
                   colors: [Color(red: 0.20, green: 0.82, blue: 0.62), Color(red: 0.05, green: 0.52, blue: 0.62)],
                   metric: !ready ? nil : model.safeBytes > 0 ? "\(format(model.safeBytes)) ready" : "All clean", recommended: true, action: model.quickClean)
          .keyboardShortcut(.defaultAction)
        ActionCard(symbol: "magnifyingglass", title: "Scan & Review", detail: "See everything, pick what goes.",
                   colors: [Color(red: 0.35, green: 0.62, blue: 1.0), Color(red: 0.36, green: 0.36, blue: 0.92)],
                   metric: !ready ? nil : model.foundBytes > 0 ? "\(format(model.foundBytes)) found" : "Nothing found", action: { model.scan() })
        ActionCard(symbol: "trash", title: "Uninstall Apps", detail: "Apps and everything they left.",
                   colors: [Color(red: 1.0, green: 0.45, blue: 0.55), Color(red: 0.93, green: 0.38, blue: 0.22)],
                   metric: model.apps.isEmpty ? nil : "\(model.apps.count) apps", action: model.openUninstall)
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
  }
}

struct Disk {
  let total: Int64
  let free: Int64

  static func now() -> Disk {
    let values = try? URL(fileURLWithPath: NSHomeDirectory())
      .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
    return Disk(total: Int64(values?.volumeTotalCapacity ?? 1), free: values?.volumeAvailableCapacityForImportantUsage ?? 0)
  }
}

/// Interactive ring: used space, what can be reclaimed, what was reclaimed this session, and free space.
/// Hover a part of the ring or the legend to see its details in the middle.
struct DiskRing: View {
  enum Part: CaseIterable { case used, reclaimable, reclaimed, free }

  let disk: Disk
  let startFree: Int64
  /// Freed this session.
  let reclaimed: Int64
  /// Safe bytes Quick Clean would free; nil until the background check finishes.
  var safe: Int64?
  var more: Int64 = 0
  var checking = false
  @State private var shown = false
  @State private var hovered: Part?

  private let size: CGFloat = 190
  private let width: CGFloat = 18

  var body: some View {
    let total = Double(max(1, disk.total))
    let used = min(1, max(0, Double(disk.total - disk.free) / total))
    // Small amounts get a minimum visible length so they don't vanish on a big disk.
    let visible = { (bytes: Int64) in bytes > 0 ? max(0.012, Double(bytes) / total) : 0 }
    let canReclaim = min(used, visible(safe ?? 0))
    // Space freed this session now sits in "free", right after used space: where it came from.
    let wasReclaimed = min(1 - used, visible(reclaimed))
    let ranges: [Part: ClosedRange<Double>] = [
      .used: 0...used,
      .reclaimable: (used - canReclaim)...used,
      .reclaimed: used...(used + wasReclaimed),
      .free: (used + wasReclaimed)...1,
    ]

    VStack(spacing: 14) {
      ZStack {
        Circle().stroke(Color.secondary.opacity(0.14), lineWidth: width)
          .opacity(dim(.free))
        arc(ranges[.used]!, style: AnyShapeStyle(Color.secondary.opacity(0.45)), part: .used)
        if canReclaim > 0 { arc(ranges[.reclaimable]!, style: AnyShapeStyle(Brand.gradient), part: .reclaimable, glow: Brand.teal) }
        if wasReclaimed > 0 { arc(ranges[.reclaimed]!, style: AnyShapeStyle(Reclaimed.gradient), part: .reclaimed, glow: Reclaimed.color) }
        center
      }
      .frame(width: size, height: size)
      .contentShape(Circle())
      .onContinuousHover { phase in
        guard case .active(let point) = phase else { hovered = nil; return }
        hovered = part(at: point, ranges: ranges)
      }
      .animation(.smooth(duration: 0.9), value: safe)
      .animation(.smooth(duration: 0.9), value: reclaimed)
      .animation(.smooth(duration: 0.2), value: hovered)

      VStack(spacing: 6) {
        HStack(spacing: 12) {
          legend(.used, "Used", Color.secondary.opacity(0.45))
          legend(.reclaimable, "Can reclaim", Brand.teal)
          if reclaimed > 0 { legend(.reclaimed, "Reclaimed", Reclaimed.color) }
          legend(.free, "Free", Color.secondary.opacity(0.2))
        }
        if reclaimed > 0 {
          HStack(spacing: 6) {
            Text(format(startFree)).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").foregroundStyle(Reclaimed.color)
            Text("\(format(disk.free)) free").foregroundStyle(Reclaimed.color).fontWeight(.semibold)
          }
          .font(.caption)
          .help("Free space when you opened Reclaim, and now")
        } else {
          Text(safe == nil ? "Checking what can be reclaimed…"
               : more > 0 ? "Up to \(format(more)) more after review" : " ")
            .font(.caption2).foregroundStyle(.tertiary)
        }
      }
    }
    .onAppear { withAnimation(.smooth(duration: 1.1)) { shown = true } }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(format(disk.free)) free of \(format(disk.total))"
                        + (safe.map { ", \(format($0)) can be reclaimed" } ?? "")
                        + (reclaimed > 0 ? ", \(format(reclaimed)) reclaimed this session" : ""))
  }

  @ViewBuilder private var center: some View {
    VStack(spacing: 2) {
      switch hovered {
      case .used:
        headline(format(disk.total - disk.free)); caption("used")
      case .reclaimable:
        headline(format(safe ?? 0), Brand.teal); caption("safe to reclaim now")
      case .reclaimed:
        headline(format(reclaimed), Reclaimed.color); caption("reclaimed this session")
        caption("from \(format(startFree)) free")
      case .free:
        headline(format(disk.free)); caption("free now")
      case nil:
        headline(format(disk.free)); caption("free of \(format(disk.total))")
        if reclaimed > 0 {
          Text("+\(format(reclaimed)) this session").font(.caption.weight(.semibold)).foregroundStyle(Reclaimed.color).padding(.top, 2)
        } else if let safe, safe > 0 {
          Text("+\(format(safe)) after cleaning").font(.caption.weight(.semibold)).foregroundStyle(Brand.teal).padding(.top, 2)
        } else if checking {
          ProgressView().controlSize(.mini).padding(.top, 4)
        }
      }
    }
    .multilineTextAlignment(.center)
    .frame(width: size - width * 2 - 16)
    .contentTransition(.numericText())
    .allowsHitTesting(false)
  }

  private func headline(_ text: String, _ color: Color = .primary) -> some View {
    Text(text).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
      .minimumScaleFactor(0.7).lineLimit(1)
  }

  private func caption(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
  }

  private func arc(_ range: ClosedRange<Double>, style: AnyShapeStyle, part: Part, glow: Color? = nil) -> some View {
    Circle()
      .trim(from: shown ? range.lowerBound : 0, to: shown ? range.upperBound : 0)
      .stroke(style, style: StrokeStyle(lineWidth: hovered == part ? width + 6 : width, lineCap: .butt))
      .rotationEffect(.degrees(-90))
      .shadow(color: (glow ?? .clear).opacity(hovered == part ? 0.8 : 0.5), radius: glow == nil ? 0 : 9)
      .opacity(dim(part))
  }

  private func dim(_ part: Part) -> Double { hovered == nil || hovered == part ? 1 : 0.35 }

  private func legend(_ part: Part, _ label: String, _ color: Color) -> some View {
    LegendDot(color: color, label: label)
      .opacity(dim(part) == 1 ? 1 : 0.5)
      .onHover { hovered = $0 ? part : nil }
  }

  /// Which part of the ring is under the pointer. Tiny arcs get a wider hit area so they stay hoverable.
  private func part(at point: CGPoint, ranges: [Part: ClosedRange<Double>]) -> Part? {
    let dx = point.x - size / 2, dy = point.y - size / 2
    let distance = (dx * dx + dy * dy).squareRoot()
    guard abs(distance - (size - width) / 2) < width else { return nil }
    var angle = atan2(dx, -dy) / (2 * .pi)  // 0 at the top, clockwise
    if angle < 0 { angle += 1 }
    let slack = 0.015
    for part in [Part.reclaimed, .reclaimable] {
      if let range = ranges[part], range.upperBound > range.lowerBound,
         angle >= range.lowerBound - slack, angle <= range.upperBound + slack { return part }
    }
    return angle <= ranges[.used]!.upperBound ? .used : .free
  }
}

enum Reclaimed {
  static let color = Color(red: 0.42, green: 0.90, blue: 0.45)
  static let gradient = LinearGradient(colors: [Color(red: 0.62, green: 0.95, blue: 0.40), Color(red: 0.25, green: 0.80, blue: 0.50)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct LegendDot: View {
  let color: Color
  let label: String

  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(label).font(.caption2).foregroundStyle(.secondary)
    }
  }
}

/// One of the three choices on the home screen: icon, title, short line, and a live number.
struct ActionCard: View {
  let symbol: String
  let title: String
  let detail: String
  let colors: [Color]
  /// Shown at the bottom once known, e.g. "8.6 GB ready".
  var metric: String?
  var recommended = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    let tint = colors.first ?? Brand.teal
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
          Spacer()
          if recommended {
            Text("Recommended")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(Brand.teal)
              .padding(.horizontal, 8).padding(.vertical, 3)
              .background(Brand.teal.opacity(0.14), in: Capsule())
          }
        }
        Text(title).font(.system(size: 16, weight: .semibold, design: .rounded)).padding(.top, 14)
        Text(detail).font(.callout).foregroundStyle(.secondary).padding(.top, 2)
        Divider().padding(.vertical, 12).opacity(0.6)
        HStack {
          if let metric {
            Text(metric).font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
              .contentTransition(.numericText())
          } else {
            ProgressView().controlSize(.mini)
          }
          Spacer()
          Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(hovering ? .white : .secondary)
            .frame(width: 24, height: 24)
            .background(hovering ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary), in: Circle())
            .offset(x: hovering ? 2 : 0)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        shape.fill(.quaternary.opacity(hovering ? 0.7 : 0.45))
        if recommended { shape.fill(Brand.teal.opacity(0.06)) }
      }
      .overlay {
        shape.strokeBorder(recommended ? AnyShapeStyle(Brand.gradient.opacity(0.9)) : AnyShapeStyle(.white.opacity(hovering ? 0.14 : 0.07)),
                           lineWidth: recommended ? 1.5 : 1)
      }
      .shadow(color: (recommended ? Brand.teal : .black).opacity(hovering ? 0.28 : 0.12), radius: hovering ? 16 : 8, y: hovering ? 7 : 3)
      .offset(y: hovering ? -2 : 0)
      .contentShape(shape)
      .animation(.smooth(duration: 0.18), value: hovering)
      .animation(.smooth, value: metric)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityHint(metric ?? detail)
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
        .contentTransition(.numericText())
      if model.sessionFreed > result.freedBytes {
        SessionBadge(model: model)
      }
      if result.trashedBytes > 0 {
        Text("\(format(result.trashedBytes)) moved to the Trash, so you can still get it back.").foregroundStyle(.secondary)
      }
      if !result.failures.isEmpty {
        Text("\(result.failures.count) item(s) couldn't be removed; they may be in use.")
          .foregroundStyle(.secondary)
          .help(result.failures.joined(separator: "\n"))
      }
      HStack(spacing: 12) {
        Button("Scan Again") { model.scan(force: true) }.controlSize(.large)
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
      .frame(maxWidth: Layout.readable)
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
        Button("Scan Again") { model.scan(force: true) }
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
    // Line the bar up with the list above instead of the window edges.
    .padding(.horizontal, 28).frame(maxWidth: Layout.readable).frame(maxWidth: .infinity).padding(.vertical, 14)
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
          Label {
            Text(message.text)
          } icon: {
            Image(systemName: message.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .foregroundStyle(message.ok ? Brand.teal : .orange)
          }
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background((message.ok ? Brand.teal : .orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if let app = model.appToRemove { planView(app) } else { appList }
      }
      .padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 20)
      .frame(maxWidth: Layout.readable)
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
          if !FileManager.default.isWritableFile(atPath: app.url.path) {
            Label("Installed for everyone on this Mac, so macOS will ask for your password.", systemImage: "lock.fill")
              .font(.callout).foregroundStyle(.orange)
          }
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
    // Line the bar up with the list above instead of the window edges.
    .padding(.horizontal, 28).frame(maxWidth: Layout.readable).frame(maxWidth: .infinity).padding(.vertical, 14)
    .background(.bar)
  }
}

/// "3.4 GB freed this session · 20 GB all time", shown on home and after cleaning.
struct SessionBadge: View {
  let model: Model

  var body: some View {
    let parts = [
      model.sessionFreed > 0 ? "\(format(model.sessionFreed)) freed this session" : nil,
      model.sessionTrashed > 0 ? "\(format(model.sessionTrashed)) in the Trash" : nil,
      model.lifetimeFreed > model.sessionFreed ? "\(format(model.lifetimeFreed)) all time" : nil,
    ].compactMap { $0 }
    Label(parts.joined(separator: " · "), systemImage: "sparkles")
      .font(.callout.weight(.medium))
      .foregroundStyle(Brand.teal)
      .padding(.horizontal, 12).padding(.vertical, 6)
      .background(Brand.teal.opacity(0.12), in: Capsule())
      .contentTransition(.numericText())
      .help("Space in the Trash is freed when you empty the Trash.")
  }
}
