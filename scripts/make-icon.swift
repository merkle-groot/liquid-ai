// Renders the 1024x1024 app icon (opaque, no alpha) — run: swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// Background gradient: deep indigo -> liquid blue
let bg = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.07, green: 0.06, blue: 0.20, alpha: 1),
    CGColor(srgbRed: 0.18, green: 0.32, blue: 0.85, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Droplet: circle bottom + pointed top
let cx = s / 2, cy = s * 0.42, r = s * 0.25
let drop = CGMutablePath()
drop.move(to: CGPoint(x: cx, y: s * 0.84))
drop.addCurve(to: CGPoint(x: cx + r, y: cy),
              control1: CGPoint(x: cx + r * 0.25, y: s * 0.70),
              control2: CGPoint(x: cx + r, y: cy + r * 0.75))
drop.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
drop.addCurve(to: CGPoint(x: cx, y: s * 0.84),
              control1: CGPoint(x: cx - r, y: cy + r * 0.75),
              control2: CGPoint(x: cx - r * 0.25, y: s * 0.70))
drop.closeSubpath()

ctx.saveGState()
ctx.addPath(drop)
ctx.clip()
let fill = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.55, green: 0.95, blue: 1.0, alpha: 1),
    CGColor(srgbRed: 0.36, green: 0.48, blue: 0.96, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(fill, start: CGPoint(x: cx, y: s * 0.84), end: CGPoint(x: cx, y: cy - r), options: [])
ctx.restoreGState()

// Highlight
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
ctx.fillEllipse(in: CGRect(x: cx - r * 0.55, y: cy + r * 0.05, width: r * 0.32, height: r * 0.45))

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
let out = URL(fileURLWithPath: "LFM3Chat/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
