#!/usr/bin/env swift
import AppKit

// ── Inline the LightRenderer & LightColor (standalone) ──────────

struct LightColor {
    let base: NSColor, bright: NSColor, dark: NSColor
    static let green = LightColor(
        base:   NSColor(red: 0.00, green: 0.86, blue: 0.22, alpha: 1),
        bright: NSColor(red: 0.35, green: 1.00, blue: 0.55, alpha: 1),
        dark:   NSColor(red: 0.00, green: 0.38, blue: 0.08, alpha: 1))
    static let red = LightColor(
        base:   NSColor(red: 0.94, green: 0.14, blue: 0.04, alpha: 1),
        bright: NSColor(red: 1.00, green: 0.48, blue: 0.28, alpha: 1),
        dark:   NSColor(red: 0.42, green: 0.02, blue: 0.00, alpha: 1))
}

enum LED {
    static func rgba(_ color: NSColor, _ alpha: CGFloat) -> [CGFloat] {
        guard let rgb = color.usingColorSpace(.sRGB) else { return [0,0,0,alpha] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, alpha]
    }
    static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> [CGFloat] { [r,g,b,a] }
    static func rect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    static func draw(in ctx: CGContext, center: CGPoint, radius: CGFloat, bezelW: CGFloat, on: Bool, color: LightColor) {
        // Glow
        if on {
            let layers: [(CGFloat, CGFloat)] = [(radius + bezelW + radius * 0.05, 0.10), (radius + bezelW * 0.6, 0.18)]
            for (r, a) in layers {
                ctx.addEllipse(in: rect(center: center, radius: r))
                ctx.setFillColor(color.base.withAlphaComponent(a).cgColor)
                ctx.fillPath()
            }
        }

        // Bezel
        let outerR = radius + bezelW
        ctx.addEllipse(in: rect(center: center, radius: outerR))
        ctx.setFillColor(CGColor(gray: 0.18, alpha: 1))
        ctx.fillPath()

        // Bezel 3D highlight
        ctx.saveGState()
        ctx.addEllipse(in: rect(center: center, radius: outerR))
        ctx.clip()
        if let hg = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                               colorComponents: [1,1,1,0.18, 0,0,0,0, 0,0,0,0] as [CGFloat],
                               locations: [0, 0.35, 1], count: 3) {
            ctx.drawLinearGradient(hg,
                start: CGPoint(x: center.x, y: center.y + outerR),
                end:   CGPoint(x: center.x, y: center.y - outerR), options: [])
        }
        ctx.restoreGState()

        // Inner bezel ring
        ctx.addEllipse(in: rect(center: center, radius: radius))
        ctx.setStrokeColor(CGColor(gray: 0.28, alpha: 0.6))
        ctx.setLineWidth(bezelW * 0.6)
        ctx.strokePath()

        // Light body
        let hotSpot = CGPoint(x: center.x - radius * 0.18, y: center.y + radius * 0.18)
        let comps: [CGFloat] = on
            ? rgba(1,1,1,1) + rgba(1,1,1,1) + rgba(color.bright,1) + rgba(color.base,1) + rgba(color.dark,0.95)
            : rgba(color.dark,0.55) + rgba(color.dark,0.35) + rgba(color.dark,0.18) + rgba(color.dark,0.08)
        let locs: [CGFloat] = on ? [0, 0.08, 0.35, 0.72, 1] : [0, 0.25, 0.55, 1]

        if let grad = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                 colorComponents: comps, locations: locs, count: locs.count) {
            ctx.saveGState()
            ctx.addEllipse(in: rect(center: center, radius: radius))
            ctx.clip()
            ctx.drawRadialGradient(grad,
                startCenter: hotSpot, startRadius: radius * 0.02,
                endCenter: center, endRadius: radius, options: [])
            ctx.restoreGState()
        }

        // Inner shadow
        if on {
            ctx.addEllipse(in: rect(center: center, radius: radius).insetBy(dx: radius * 0.04, dy: radius * 0.04))
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
            ctx.setLineWidth(radius * 0.08)
            ctx.strokePath()
        }

        // Specular dot
        if on {
            let dotR = radius * 0.01
            let dotC = CGPoint(x: center.x - radius * 0.32, y: center.y + radius * 0.38)
            let comps: [CGFloat] = [1,1,1,0.55, 1,1,1,0]
            if let grad = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                     colorComponents: comps, locations: [0,1], count: 2) {
                ctx.saveGState()
                ctx.addEllipse(in: rect(center: dotC, radius: dotR))
                ctx.clip()
                ctx.drawRadialGradient(grad, startCenter: dotC, startRadius: 0, endCenter: dotC, endRadius: dotR, options: [])
                ctx.restoreGState()
            }
        }
    }
}

// ── Generate icon ───────────────────────────────────────────────

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let iconsetDir = projectDir.appendingPathComponent("BusyLight.iconset")

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for size in sizes {
    let canvas = CGFloat(size)
    let img = NSImage(size: NSSize(width: canvas, height: canvas))
    img.lockFocus()

    // Dark rounded-rect background
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: canvas, height: canvas),
                              xRadius: canvas * 0.225, yRadius: canvas * 0.225)
    NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1).setFill()
    bgPath.fill()

    // LED in center
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let radius = canvas * 0.27
    let bezelW = radius * 0.13

    if let ctx = NSGraphicsContext.current?.cgContext {
        LED.draw(in: ctx, center: center, radius: radius, bezelW: bezelW, on: true, color: .green)
    }

    img.unlockFocus()

    // Save PNG
    let name = size == 1024 ? "icon_512x512@2x" : "icon_\(size)x\(size)"
    let pngURL = iconsetDir.appendingPathComponent("\(name).png")
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: pngURL)
    print("  \(name).png")
}

// Also generate @2x sizes
for size in [16, 32, 64, 128, 256, 512] {
    let name = "icon_\(size)x\(size)@2x"
    // Already generated as the next size up, but with the correct name
    let src = iconsetDir.appendingPathComponent("icon_\(size*2)x\(size*2).png")
    let dst = iconsetDir.appendingPathComponent("\(name).png")
    if FileManager.default.fileExists(atPath: src.path) {
        try FileManager.default.copyItem(at: src, to: dst)
        print("  \(name).png (copy)")
    }
}

// Convert to .icns
let icnsURL = projectDir.appendingPathComponent("dist").appendingPathComponent("BusyLight.app")
    .appendingPathComponent("Contents").appendingPathComponent("Resources").appendingPathComponent("AppIcon.icns")
try? FileManager.default.removeItem(at: icnsURL)
try FileManager.default.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", "-o", icnsURL.path, iconsetDir.path]
task.launch()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("\n✅ AppIcon.icns created at \(icnsURL.path)")
} else {
    print("\n❌ iconutil failed with exit code \(task.terminationStatus)")
}

// Cleanup
try? FileManager.default.removeItem(at: iconsetDir)
