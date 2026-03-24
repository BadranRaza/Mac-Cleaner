import SwiftUI
import AppKit
import MacCleanerCore

private enum Palette {
  static let canvas = Color(red: 0.09, green: 0.08, blue: 0.07)
  static let paper = Color(red: 0.94, green: 0.90, blue: 0.84)
  static let ivory = Color(red: 0.98, green: 0.95, blue: 0.90)
  static let ink = Color(red: 0.16, green: 0.13, blue: 0.11)
  static let mutedInk = Color(red: 0.45, green: 0.40, blue: 0.35)
  static let sand = Color(red: 0.76, green: 0.66, blue: 0.48)
  static let amber = Color(red: 0.62, green: 0.48, blue: 0.24)
  static let coral = Color(red: 0.44, green: 0.16, blue: 0.18)
  static let sage = Color(red: 0.24, green: 0.30, blue: 0.24)
  static let sea = Color(red: 0.23, green: 0.28, blue: 0.26)
  static let alabaster = Color(red: 0.97, green: 0.94, blue: 0.89)
  static let smoke = Color(red: 0.78, green: 0.74, blue: 0.67)
}

@main
struct MacCleanerGUI: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var scanStore = ScanStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(scanStore)
        .preferredColorScheme(.dark)
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 1180, height: 820)
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
        VStack(spacing: 22) {
          HeroCard(
            report: scanStore.lastReport,
            selectedRootCount: scanStore.selectedRoots.count,
            isScanning: scanStore.isScanning
          )

          if scanStore.lastReport == nil {
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .top, spacing: 22) {
                leftColumn
                  .frame(maxWidth: 420)
                idleRightColumn
              }

              VStack(spacing: 22) {
                leftColumn
                idleRightColumn
              }
            }
          } else {
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .top, spacing: 22) {
                leftColumn
                  .frame(maxWidth: 380)
                rightColumn
              }

              VStack(spacing: 22) {
                leftColumn
                rightColumn
              }
            }
          }
        }
        .padding(28)
        .padding(.bottom, 32)
      }
    }
    .frame(minWidth: 980, minHeight: 700)
    .animation(.spring(response: 0.45, dampingFraction: 0.86), value: scanStore.isScanning)
    .animation(.spring(response: 0.45, dampingFraction: 0.86), value: scanStore.lastReport?.scanId)
  }

  private var leftColumn: some View {
    VStack(spacing: 22) {
      ScanControlCard()

      if scanStore.isScanning {
        ProgressPanel()
          .transition(.opacity.combined(with: .move(edge: .top)))
      } else if scanStore.lastReport == nil && scanStore.status != "Ready" {
        StatusCard(status: scanStore.status)
      }
    }
  }

  @ViewBuilder
  private var rightColumn: some View {
    if let report = scanStore.lastReport {
      VStack(spacing: 22) {
        SummaryCard(report: report)
        ResultsCard(items: report.items)
      }
    }
  }

  private var idleRightColumn: some View {
    IdleOverviewCard()
  }
}

private struct AppBackdrop: View {
  var body: some View {
    ZStack {
      Palette.canvas
        .ignoresSafeArea()

      LinearGradient(
        colors: [
          Palette.canvas,
          Color(red: 0.12, green: 0.10, blue: 0.09),
          Palette.canvas
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      Circle()
        .fill(
          RadialGradient(
            colors: [Palette.coral.opacity(0.18), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: 340
          )
        )
        .frame(width: 440, height: 440)
        .offset(x: 340, y: -220)

      Circle()
        .fill(
          RadialGradient(
            colors: [Palette.sand.opacity(0.12), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: 360
          )
        )
        .frame(width: 460, height: 460)
        .offset(x: -360, y: 260)

      Circle()
        .fill(
          RadialGradient(
            colors: [Palette.sage.opacity(0.11), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: 360
          )
        )
        .frame(width: 420, height: 420)
        .offset(x: 120, y: 260)

      DiagonalPattern()
        .opacity(0.20)
        .ignoresSafeArea()
    }
  }
}

private struct MacPanel<Content: View>: View {
  enum Style {
    case light
    case dark
  }

  private let tint: Color
  private let style: Style
  private let content: () -> Content

  init(
    tint: Color = Palette.paper,
    style: Style = .light,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.tint = tint
    self.style = style
    self.content = content
  }

  var body: some View {
    content()
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .fill(backgroundGradient)
          .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
              .stroke(borderColor, lineWidth: 1)
          )
          .shadow(color: Color.black.opacity(style == .dark ? 0.30 : 0.15), radius: 28, x: 0, y: 18)
      )
  }

  private var backgroundGradient: LinearGradient {
    switch style {
    case .light:
      return LinearGradient(
        colors: [
          tint.opacity(0.98),
          Palette.ivory.opacity(0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .dark:
      return LinearGradient(
        colors: [
          tint.opacity(0.98),
          Palette.ink.opacity(0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }

  private var borderColor: Color {
    switch style {
    case .light:
      return Palette.ink.opacity(0.08)
    case .dark:
      return Palette.sand.opacity(0.30)
    }
  }
}

private struct HeroCard: View {
  let report: CleanupScanReport?
  let selectedRootCount: Int
  let isScanning: Bool

  var body: some View {
    MacPanel(tint: Palette.canvas, style: .dark) {
      HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading, spacing: 14) {
          Text("Mac Cleaner")
            .font(.system(size: 42, weight: .bold, design: .serif))
            .foregroundStyle(Palette.alabaster)

          IconPill(systemName: "folder.fill", value: "\(selectedRootCount)", accent: Palette.sand)
        }

        Spacer(minLength: 20)

        VStack(alignment: .trailing, spacing: 10) {
          HStack(spacing: 8) {
            Image(systemName: report == nil ? "sparkles" : "arrow.down.circle.fill")
              .foregroundStyle(Palette.sand)
            Text(report.map { formattedByteCount($0.totalEstimatedBytes) } ?? "Ready")
              .font(.system(size: 32, weight: .bold, design: .serif))
              .foregroundStyle(Palette.alabaster)
          }

          if let report {
            HStack(spacing: 8) {
              IconPill(systemName: "square.stack.3d.up.fill", value: "\(report.summary.total)", accent: Palette.sea)
              IconPill(systemName: "scope", value: "\(report.scannerCount)", accent: Palette.sage)
            }
          }
        }
        .padding(18)
        .frame(width: 210)
        .background(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
              RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Palette.sand.opacity(0.25), lineWidth: 1)
            )
        )
      }
    }
  }
}

private struct IdleOverviewCard: View {
  var body: some View {
    MacPanel(tint: Palette.ink, style: .dark) {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: 10) {
          Image(systemName: "sparkles.rectangle.stack.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Palette.sand)
          Text("First Scan")
            .font(.system(size: 34, weight: .bold, design: .serif))
            .foregroundStyle(Palette.alabaster)
        }

        HStack(spacing: 14) {
          OnboardingTile(systemName: "folder.badge.plus", title: "Folders", accent: Palette.sand)
          OnboardingTile(systemName: "slider.horizontal.3", title: "Scope", accent: Palette.sage)
          OnboardingTile(systemName: "magnifyingglass", title: "Scan", accent: Palette.amber)
        }

        Rectangle()
          .fill(Palette.sand.opacity(0.18))
          .frame(height: 1)

        HStack(spacing: 14) {
          CapabilityTile(systemName: "hammer.circle.fill", title: "Xcode", accent: Palette.sand)
          CapabilityTile(systemName: "cube.box.fill", title: "Unity", accent: Palette.sage)
          CapabilityTile(systemName: "lock.shield.fill", title: "Scoped", accent: Palette.sea)
        }

        Spacer(minLength: 0)

        HStack(spacing: 12) {
          IconPill(systemName: "arrow.down.circle.fill", accent: Palette.sand)
          IconPill(systemName: "eye.fill", accent: Palette.amber)
          IconPill(systemName: "checkmark.shield.fill", accent: Palette.sage)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 470, alignment: .topLeading)
    }
  }
}

private struct ScanControlCard: View {
  @EnvironmentObject var scanStore: ScanStore
  @State private var showAdvancedOptions = false

  var body: some View {
    MacPanel(tint: Palette.ink, style: .dark) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Palette.sand)
          Text("Setup")
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(Palette.alabaster)
        }

        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            Spacer()

            Button {
              scanStore.addScanRoots()
            } label: {
              Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(LuxurySecondaryButtonStyle())
            .help("Add scan folders")
            .accessibilityLabel("Add scan folders")

            Button {
              scanStore.clearScanRoots()
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(LuxurySecondaryButtonStyle())
            .disabled(scanStore.selectedRoots.isEmpty)
            .help("Clear scan folders")
            .accessibilityLabel("Clear scan folders")
          }

          if !scanStore.selectedRoots.isEmpty {
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
            .padding(10)
            .background(Color.white.opacity(0.05))
            .overlay(
              RoundedRectangle(cornerRadius: 18)
                .stroke(Palette.sand.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
          }
        }

        Rectangle()
          .fill(Palette.sand.opacity(0.18))
          .frame(height: 1)
        HStack {
          Spacer()
          Button {
            scanStore.scan()
          } label: {
            Image(systemName: scanStore.isScanning ? "hourglass" : "magnifyingglass")
              .font(.system(size: 18, weight: .semibold))
              .frame(width: 48, height: 44)
          }
          .buttonStyle(LuxuryPrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
          .disabled(scanStore.isScanning || !scanStore.canScan)
          .help(scanStore.isScanning ? "Scanning" : "Run scan")
          .accessibilityLabel(scanStore.isScanning ? "Scanning" : "Run scan")
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
        .foregroundStyle(Palette.sand)
      Text(url.path)
        .font(.system(size: 16, design: .monospaced))
        .foregroundStyle(Palette.alabaster)
        .lineLimit(1)
      Spacer(minLength: 6)
      Button {
        onRemove()
      } label: {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .foregroundStyle(Palette.smoke)
      .help("Remove folder")
    }
    .padding(.horizontal, 6)
  }
}

private struct ProgressPanel: View {
  @EnvironmentObject var scanStore: ScanStore

  var body: some View {
    MacPanel(tint: Palette.ink, style: .dark) {
      HStack(alignment: .center, spacing: 12) {
        ProgressView()
          .controlSize(.large)
          .scaleEffect(0.9)
          .tint(Palette.sand)
        Text(scanStore.status)
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .foregroundStyle(Palette.alabaster)
        Spacer()
      }
    }
  }
}

private struct StatusCard: View {
  let status: String

  var body: some View {
    MacPanel(tint: Palette.ink, style: .dark) {
      HStack(spacing: 12) {
        Image(systemName: "waveform.path.ecg.rectangle")
          .foregroundStyle(Palette.sand)
        Text(status)
          .font(.system(size: 18, weight: .semibold, design: .rounded))
          .foregroundStyle(Palette.alabaster)
        Spacer()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SummaryCard: View {
  let report: CleanupScanReport

  var body: some View {
    MacPanel(tint: Palette.ink, style: .dark) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 16) {
          HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
              .foregroundStyle(Palette.sand)
            Text(formattedByteCount(report.totalEstimatedBytes))
              .font(.system(size: 42, weight: .bold, design: .serif))
              .foregroundStyle(Palette.alabaster)
          }

          Spacer()

          HStack(spacing: 12) {
            ScoreBadge(value: report.summary.high, systemName: "checkmark.shield.fill", color: Palette.sage)
            ScoreBadge(value: report.summary.medium, systemName: "eye.fill", color: Palette.amber)
            ScoreBadge(value: report.summary.total, systemName: "square.stack.3d.up.fill", color: Palette.sea)
          }
        }

        HStack(spacing: 10) {
          IconPill(systemName: "clock.fill", value: report.scannedAt.formatted(date: .omitted, time: .shortened), accent: Palette.smoke)
          IconPill(systemName: "folder.fill", value: "\(report.scannedRoots.count)", accent: Palette.sand)
        }

        if !report.categorySummary.isEmpty {
          FlowLayout {
            ForEach(report.categorySummary.keys.sorted(), id: \.self) { key in
              IconPill(
                systemName: iconName(for: CleanupCategory(rawValue: key) ?? .xcodeArtifacts),
                value: "\(report.categorySummary[key, default: 0])",
                accent: colorForCategoryKey(key)
              )
            }
          }
        }
      }
    }
  }
}

private struct ScoreBadge: View {
  let value: Int
  let systemName: String
  let color: Color

  var body: some View {
    VStack {
      Image(systemName: systemName)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(color)
      Text("\(value)")
        .font(.system(size: 24, weight: .bold, design: .serif))
        .foregroundStyle(Palette.alabaster)
    }
    .frame(width: 72, height: 68)
    .background(
      LinearGradient(
        colors: [Color.white.opacity(0.05), color.opacity(0.20)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(color.opacity(0.6), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}

private struct ResultsCard: View {
  let items: [CleanupFinding]

  var body: some View {
    MacPanel(tint: Palette.ink, style: .dark) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: "sparkles.rectangle.stack.fill")
            .foregroundStyle(Palette.sand)
          Text("\(items.count)")
            .font(.system(size: 30, weight: .bold, design: .serif))
            .foregroundStyle(Palette.alabaster)
        }

        if items.isEmpty {
          Text("No cleanup findings detected in the selected folders.")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.smoke)
            .padding(.vertical, 8)
        } else {
          VStack(spacing: 14) {
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
    MacPanel(tint: Palette.canvas, style: .dark) {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 14)
            .fill(colorForCategory(item.category).opacity(0.16))
            .frame(width: 44, height: 44)
          Image(systemName: iconName(for: item.category))
            .foregroundColor(colorForCategory(item.category))
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            IconPill(systemName: iconName(for: item.category), accent: colorForCategory(item.category))
            IconPill(systemName: scannerIconName(item.sourceScanner), accent: Palette.sea)
          }

          Text(item.title)
            .font(.system(size: 21, weight: .bold, design: .serif))
            .foregroundStyle(Palette.alabaster)
            .lineLimit(2)

          Text(item.subtitle)
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundStyle(Palette.smoke)

          if let metadata = item.metadata {
            Text(metadata)
              .font(.system(size: 15, weight: .regular, design: .rounded))
              .foregroundStyle(Palette.smoke)
          }

          Text(item.path)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Palette.smoke)
            .lineLimit(2)

          Text(item.recommendedAction)
            .font(.system(size: 16, design: .rounded))
            .foregroundStyle(Palette.alabaster)

          VStack(alignment: .leading, spacing: 7) {
            FlowLayout {
              ForEach(item.cleanupTargets, id: \.self) { target in
                HStack(spacing: 6) {
                  Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                  Text(target.name)
                }
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Color.white.opacity(0.05))
                  .clipShape(Capsule())
                  .foregroundStyle(Palette.alabaster)
                  .font(.system(size: 12, design: .rounded))
                  .overlay(
                    Capsule().stroke(Palette.sand.opacity(0.18), lineWidth: 1)
                  )
              }
            }
          }

          Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "folder")
              Text("Reveal in Finder")
            }
          }
          .buttonStyle(LuxurySecondaryButtonStyle())
          .help("Reveal in Finder")
          .accessibilityLabel("Reveal in Finder")
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 10) {
          HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
              .foregroundStyle(Palette.sand)
            Text(formattedByteCount(item.estimatedBytes))
              .font(.system(size: 28, weight: .bold, design: .serif))
              .foregroundStyle(Palette.alabaster)
          }
          ConfidenceChip(confidence: item.confidenceScore, band: item.confidenceBand)
        }
      }
    }
  }
}

private struct ConfidenceChip: View {
  let confidence: Int
  let band: CleanupConfidenceBand

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: confidenceIconName(for: band))
        .foregroundStyle(bandColor)
      Text("\(confidence)")
        .font(.system(size: 10, weight: .bold, design: .rounded))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      LinearGradient(
        colors: [Color.white.opacity(0.05), bandColor.opacity(0.22)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(Capsule())
    .foregroundStyle(Palette.alabaster)
    .overlay(
      Capsule().stroke(bandColor.opacity(0.7), lineWidth: 1)
    )
  }

  private var bandColor: Color {
    switch band {
    case .high:
      return Palette.sage
    case .medium:
      return Palette.amber
    case .low:
      return Palette.coral
    }
  }
}

private struct SectionEyebrow: View {
  let title: String

  var body: some View {
    Text(title.uppercased())
      .font(.system(size: 11, weight: .bold, design: .rounded))
      .tracking(1.6)
      .foregroundStyle(Palette.smoke.opacity(0.9))
  }
}

private struct CapsuleLabel: View {
  let title: String
  let color: Color

  var body: some View {
    Text(title)
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(Palette.alabaster)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(color.opacity(0.18))
      .clipShape(Capsule())
      .overlay(
        Capsule().stroke(color.opacity(0.45), lineWidth: 1)
      )
  }
}

private struct DetailChip: View {
  enum Tone {
    case light
    case dark
  }

  let title: String
  let accent: Color
  let tone: Tone

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(accent)
        .frame(width: 7, height: 7)
      Text(title)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(Palette.alabaster)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(tone == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.04))
    .clipShape(Capsule())
    .overlay(
      Capsule().stroke(accent.opacity(tone == .dark ? 0.40 : 0.28), lineWidth: 1)
    )
  }
}

private struct IconPill: View {
  let systemName: String
  var value: String? = nil
  let accent: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .semibold))
      if let value {
        Text(value)
          .font(.system(size: 12, weight: .bold, design: .rounded))
      }
    }
    .foregroundStyle(Palette.alabaster)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.05))
    .clipShape(Capsule())
    .overlay(
      Capsule().stroke(accent.opacity(0.36), lineWidth: 1)
    )
  }
}

private struct IconField: View {
  let systemName: String
  let placeholder: String
  @Binding var text: String
  let width: CGFloat

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemName)
        .foregroundStyle(Palette.sand)
      PremiumField(placeholder: placeholder, text: $text, width: width)
    }
  }
}

private struct OnboardingTile: View {
  let systemName: String
  let title: String
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: systemName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(accent)
      Text(title)
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .foregroundStyle(Palette.alabaster)
    }
    .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(accent.opacity(0.20), lineWidth: 1)
        )
    )
  }
}

private struct CapabilityTile: View {
  let systemName: String
  let title: String
  let accent: Color

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemName)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(accent)
      Text(title)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(Palette.alabaster)
    }
    .frame(maxWidth: .infinity, minHeight: 56)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.white.opacity(0.04))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    )
  }
}

private struct PremiumField: View {
  let placeholder: String
  @Binding var text: String
  let width: CGFloat

  var body: some View {
    TextField(placeholder, text: $text)
      .textFieldStyle(.plain)
      .font(.system(size: 14, weight: .medium, design: .rounded))
      .foregroundStyle(Palette.alabaster)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(width: width)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.white.opacity(0.05))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(Palette.sand.opacity(0.18), lineWidth: 1)
          )
      )
  }
}

private struct LuxuryPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Palette.sand, Palette.amber.opacity(0.92)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(Palette.ivory.opacity(0.5), lineWidth: 1)
          )
          .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)
      )
      .opacity(configuration.isPressed ? 0.92 : 1)
      .scaleEffect(configuration.isPressed ? 0.99 : 1)
  }
}

private struct LuxurySecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold, design: .rounded))
      .foregroundStyle(Palette.alabaster)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.white.opacity(configuration.isPressed ? 0.04 : 0.06))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(Palette.sand.opacity(0.18), lineWidth: 1)
          )
      )
  }
}

private struct DiagonalPattern: View {
  var body: some View {
    GeometryReader { geometry in
      Path { path in
        let step: CGFloat = 28
        let width = geometry.size.width
        let height = geometry.size.height

        stride(from: -height, through: width, by: step).forEach { offset in
          path.move(to: CGPoint(x: offset, y: 0))
          path.addLine(to: CGPoint(x: offset + height, y: height))
        }
      }
      .stroke(Palette.sand.opacity(0.07), lineWidth: 1)
    }
  }
}

private func iconName(for category: CleanupCategory) -> String {
  switch category {
  case .unityProjects:
    return "cube.box.fill"
  case .xcodeArtifacts:
    return "hammer.circle.fill"
  case .trash:
    return "trash.fill"
  case .applicationCaches:
    return "server.rack"
  case .developerCaches:
    return "terminal.fill"
  }
}

private func colorForCategory(_ category: CleanupCategory) -> Color {
  switch category {
  case .unityProjects:
    return Palette.sage
  case .xcodeArtifacts:
    return Palette.sand
  case .trash:
    return Palette.coral
  case .applicationCaches:
    return Palette.amber
  case .developerCaches:
    return Palette.sea
  }
}

private func scannerIconName(_ scanner: String) -> String {
  let lowercased = scanner.lowercased()
  if lowercased.contains("unity") {
    return "cube.box.fill"
  }
  if lowercased.contains("xcode") {
    return "hammer.circle.fill"
  }
  if lowercased.contains("trash") {
    return "trash.fill"
  }
  if lowercased.contains("cache") {
    return "server.rack"
  }
  return "scope"
}

private func confidenceIconName(for band: CleanupConfidenceBand) -> String {
  switch band {
  case .high:
    return "checkmark.shield.fill"
  case .medium:
    return "eye.fill"
  case .low:
    return "exclamationmark.triangle.fill"
  }
}

private func colorForCategoryKey(_ key: String) -> Color {
  guard let category = CleanupCategory(rawValue: key) else {
    return Palette.sea
  }

  return colorForCategory(category)
}

private func friendlyCategoryName(_ key: String) -> String {
  switch CleanupCategory(rawValue: key) {
  case .unityProjects:
    return "Unity"
  case .xcodeArtifacts:
    return "Xcode"
  case .trash:
    return "Trash Bin"
  case .applicationCaches:
    return "App Caches"
  case .developerCaches:
    return "Dev Caches"
  case nil:
    return key
  }
}

private func formattedByteCount(_ bytes: Int64) -> String {
  let formatter = ByteCountFormatter()
  formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
  formatter.countStyle = .file
  formatter.includesUnit = true
  formatter.isAdaptive = true
  return formatter.string(fromByteCount: bytes)
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
  @Published var selectedRoots: [URL]
  @Published var isScanning: Bool = false
  @Published var status: String = "Ready"
  @Published var lastReport: CleanupScanReport?

  init() {
    selectedRoots = ScanRootBookmarkStore.loadURLs()
  }

  var canScan: Bool {
    !selectedRoots.isEmpty
  }

  func scan() {
    guard !isScanning else { return }

    guard !selectedRoots.isEmpty else {
      status = "Select at least one folder to scan."
      return
    }

    let parsedRoots = selectedRoots
      .map { $0.standardizedFileURL.path }
      .filter { !$0.isEmpty }
    let scanRoots = selectedRoots

    let options = CleanupScanOptions(
      roots: parsedRoots,
      minimumConfidence: 6,
      maxDepth: nil
    )

    isScanning = true
    status = "Starting scan..."
    lastReport = nil

    Task {
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
        self.status = "Cannot access \(denied). Re-add folder from picker."
        self.isScanning = false
        return
      }

      let report = await Self.performScan(options: options)

      for root in grantedRoots {
        root.stopAccessingSecurityScopedResource()
      }

      let reclaimable = formattedByteCount(report.totalEstimatedBytes)
      self.lastReport = report
      self.isScanning = false
      self.status = "Completed in \(report.elapsedMs)ms. Found \(report.summary.total) cleanup item(s): \(report.summary.high) high, \(report.summary.medium) medium, \(report.summary.low) low, \(reclaimable) reclaimable."
    }
  }

  private static nonisolated func performScan(options: CleanupScanOptions) async -> CleanupScanReport {
    CleanupEngine().scanReport(options: options)
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
      ScanRootBookmarkStore.save(urls: unique)
    }
  }

  func removeSelectedRoot(_ url: URL) {
    selectedRoots.removeAll {
      $0.standardizedFileURL.path == url.standardizedFileURL.path
    }
    if selectedRoots.isEmpty {
      ScanRootBookmarkStore.clear()
    } else {
      ScanRootBookmarkStore.save(urls: selectedRoots)
    }
  }

  func clearScanRoots() {
    selectedRoots = []
    ScanRootBookmarkStore.clear()
  }
}
