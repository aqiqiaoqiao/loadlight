import AppKit

// MARK: - Renderer

enum LightRenderer {

    static let canvasSize = CGSize(width: 24, height: 24)
    private static let lightRadius: CGFloat = 8.0
    private static let bezelWidth: CGFloat = 0.8

    static func makeImage(on: Bool, color: LightColor, breath: CGFloat = 1.0) -> NSImage {
        let img = NSImage(size: canvasSize)
        img.isTemplate = false
        img.lockFocus()
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        draw(in: NSGraphicsContext.current!.cgContext, center: center,
             on: on, color: color, breath: breath)
        img.unlockFocus()
        return img
    }

    static func draw(in ctx: CGContext, center: CGPoint,
                     on: Bool, color: LightColor, breath: CGFloat = 1.0) {

        // ── Glow (pulsates with breath) ─────────────────────
        if on {
            drawGlow(ctx: ctx, center: center, color: color.base, intensity: breath)
        }

        // ── Bezel ───────────────────────────────────────────
        // Bezel dims with breath so it doesn't float alone when dark
        let bezelAlpha = on ? breath : 1.0  // 0 when dark, 1 when bright
        let outerBezelR = lightRadius + bezelWidth
        let bezelRect = rect(center: center, radius: outerBezelR)
        ctx.addEllipse(in: bezelRect)
        ctx.setFillColor(CGColor(gray: 0.18, alpha: bezelAlpha))
        ctx.fillPath()

        // Bezel 3D rim highlight (also scales)
        ctx.saveGState()
        ctx.addEllipse(in: bezelRect)
        ctx.clip()
        if let hg = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                               colorComponents: [1,1,1,0.18 * bezelAlpha, 0,0,0,0, 0,0,0,0] as [CGFloat],
                               locations: [0, 0.35, 1], count: 3) {
            ctx.drawLinearGradient(hg,
                start: CGPoint(x: center.x, y: center.y + outerBezelR),
                end:   CGPoint(x: center.x, y: center.y - outerBezelR), options: [])
        }
        ctx.restoreGState()

        // Inner bezel ring
        ctx.addEllipse(in: rect(center: center, radius: lightRadius))
        ctx.setStrokeColor(CGColor(gray: 0.28, alpha: 0.6 * bezelAlpha))
        ctx.setLineWidth(0.5)
        ctx.strokePath()

        // ── Light body (brightness modulated by breath) ─────
        let bodyRect = rect(center: center, radius: lightRadius)
        let hotSpot = CGPoint(
            x: center.x - lightRadius * 0.18,
            y: center.y + lightRadius * 0.18
        )

        let comps: [CGFloat] = on
            ? rgba(1,1,1, breath)
              + rgba(1,1,1, breath * 0.95)
              + rgba(color.bright, breath)
              + rgba(color.base, breath * 0.9)
              + rgba(color.dark, 0.95 * breath)
            : rgba(color.dark, 0.55)
              + rgba(color.dark, 0.35)
              + rgba(color.dark, 0.18)
              + rgba(color.dark, 0.08)

        let locs: [CGFloat] = on
            ? [0.0, 0.08, 0.35, 0.72, 1.0]
            : [0.0, 0.25, 0.55, 1.0]

        if let grad = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                 colorComponents: comps, locations: locs, count: locs.count) {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.drawRadialGradient(grad,
                startCenter: hotSpot, startRadius: lightRadius * 0.02,
                endCenter: center,    endRadius: lightRadius, options: [])
            ctx.restoreGState()
        }

        // ── Inner shadow ring ───────────────────────────────
        if on {
            ctx.addEllipse(in: bodyRect.insetBy(dx: 0.3, dy: 0.3))
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.12 * breath))
            ctx.setLineWidth(0.6)
            ctx.strokePath()
        }

    }

    // MARK: - Color helpers

    private static func rgba(_ color: NSColor, _ alpha: CGFloat) -> [CGFloat] {
        guard let rgb = color.usingColorSpace(.sRGB) else { return [0,0,0,alpha] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, alpha]
    }
    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> [CGFloat] {
        [r,g,b,a]
    }

    // MARK: - Geometry

    private static func rect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius,
               width: radius * 2, height: radius * 2)
    }

    // MARK: - Glow (intensity modulated by breath)

    private static func drawGlow(ctx: CGContext, center: CGPoint, color: NSColor, intensity: CGFloat) {
        // Glow extent scales with breath — contracts into bezel when dim
        let extOuter: CGFloat = 1.5 * intensity
        let extInner: CGFloat = 0.7 * intensity
        let layers: [(radius: CGFloat, alpha: CGFloat)] = [
            (lightRadius + extOuter, 0.08 * intensity),
            (lightRadius + extInner, 0.16 * intensity),
        ]
        for (r, a) in layers {
            ctx.addEllipse(in: rect(center: center, radius: r))
            ctx.setFillColor(color.withAlphaComponent(a).cgColor)
            ctx.fillPath()
        }
    }

}

// MARK: - Light Color

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

