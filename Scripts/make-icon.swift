// Renders Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
  let s = CGFloat(px)
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let ctx = NSGraphicsContext.current!.cgContext

  // macOS icon grid: 824/1024 body with a soft drop shadow.
  let inset = s * 100 / 1024
  let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
  let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
  ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                color: NSColor.black.withAlphaComponent(0.35).cgColor)
  NSColor.black.setFill(); shape.fill()
  ctx.setShadow(offset: .zero, blur: 0, color: nil)
  shape.addClip()
  NSGradient(colors: [NSColor(red: 0.20, green: 0.85, blue: 0.62, alpha: 1),
                      NSColor(red: 0.04, green: 0.45, blue: 0.62, alpha: 1)])!
    .draw(in: body, angle: -65)
  NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

  let config = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
  let symbol = NSImage(systemSymbolName: "arrow.trianglehead.counterclockwise", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
  let sparkle = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)!
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: s * 0.2, weight: .bold)
      .applying(.init(paletteColors: [.white])))!
  for image in [symbol, sparkle] {
    let size = image.size
    image.draw(in: CGRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2,
                          width: size.width, height: size.height))
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
  try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
try! FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try! render(1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print("wrote \(out.path)")
