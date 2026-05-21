#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift generate_icon.swift <output-path> [size]
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024
let s = CGFloat(size)

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

// Background — indigo gradient matching Theme.asleepGradient
let bgColors = [
    CGColor(red: 0.10, green: 0.13, blue: 0.30, alpha: 1.0),
    CGColor(red: 0.20, green: 0.18, blue: 0.45, alpha: 1.0)
] as CFArray
let bgGradient = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: s),
    end: CGPoint(x: s, y: 0),
    options: []
)

// Classic crescent — two same-sized circles, second offset right & up so it bites
// the moon's right side and produces a clean leftward-opening crescent.
let moonRadius: CGFloat = s * 0.36
let moonCenter = CGPoint(x: s * 0.46, y: s * 0.50)
let cutoutRadius: CGFloat = s * 0.34
let cutoutCenter = CGPoint(x: moonCenter.x + s * 0.20, y: moonCenter.y - s * 0.04)

// Soft glow behind the moon
let glowColors = [
    CGColor(red: 1.00, green: 0.90, blue: 0.72, alpha: 0.25),
    CGColor(red: 1.00, green: 0.90, blue: 0.72, alpha: 0.00)
] as CFArray
let glowGradient = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    glowGradient,
    startCenter: moonCenter, startRadius: 0,
    endCenter: moonCenter, endRadius: moonRadius * 1.6,
    options: []
)

// Full moon, then redraw the gradient inside the cutout circle to "bite" it.
ctx.setFillColor(CGColor(red: 1.00, green: 0.93, blue: 0.78, alpha: 1.0))
ctx.fillEllipse(in: CGRect(
    x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius,
    width: moonRadius * 2, height: moonRadius * 2
))
ctx.saveGState()
ctx.beginPath()
ctx.addArc(center: cutoutCenter, radius: cutoutRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.closePath()
ctx.clip()
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: s),
    end: CGPoint(x: s, y: 0),
    options: []
)
ctx.restoreGState()

// Stars / sparkles
func drawStar(at center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha))
    let r = radius
    let r2 = radius * 0.22
    let path = CGMutablePath()
    let points: [(CGFloat, CGFloat)] = [
        (center.x, center.y - r),
        (center.x + r2, center.y - r2),
        (center.x + r, center.y),
        (center.x + r2, center.y + r2),
        (center.x, center.y + r),
        (center.x - r2, center.y + r2),
        (center.x - r, center.y),
        (center.x - r2, center.y - r2)
    ]
    path.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for p in points.dropFirst() {
        path.addLine(to: CGPoint(x: p.0, y: p.1))
    }
    path.closeSubpath()
    ctx.addPath(path)
    ctx.fillPath()
}

drawStar(at: CGPoint(x: s * 0.74, y: s * 0.30), radius: s * 0.030, alpha: 0.95)
drawStar(at: CGPoint(x: s * 0.20, y: s * 0.22), radius: s * 0.018, alpha: 0.80)
drawStar(at: CGPoint(x: s * 0.82, y: s * 0.62), radius: s * 0.014, alpha: 0.70)
drawStar(at: CGPoint(x: s * 0.27, y: s * 0.78), radius: s * 0.012, alpha: 0.55)

// Save PNG
guard let cgImage = ctx.makeImage() else { exit(2) }
let outURL = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL,
    UTType.png.identifier as CFString,
    1, nil
) else { exit(3) }
CGImageDestinationAddImage(dest, cgImage, nil)
if !CGImageDestinationFinalize(dest) { exit(4) }
print("Wrote \(size)×\(size) → \(outputPath)")
