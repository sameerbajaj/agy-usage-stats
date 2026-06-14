#!/usr/bin/swift
// Generates a 1024×1024 AppIcon PNG for agy-usage-stats.
// Usage: swift generate-icon.swift <output-path>
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon-1024.png"

let size = 1024
let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

guard let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
    print("Failed to create graphics context"); exit(1)
}
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

let full = CGRect(x: 0, y: 0, width: size, height: size)

// ── Background: purple → cyan gradient on rounded rect ──────────────────────
let cornerRadius = CGFloat(size) * 0.22
let bgPath = CGPath(roundedRect: full, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
cg.addPath(bgPath)
cg.clip()

let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradColors = [
    CGColor(colorSpace: colorSpace, components: [0.55, 0.25, 0.95, 1.0])!,  // purple
    CGColor(colorSpace: colorSpace, components: [0.25, 0.65, 1.0, 1.0])!   // cyan/blue
]
let gradient = CGGradient(colorsSpace: colorSpace,
                          colors: gradColors as CFArray,
                          locations: [0.0, 1.0])!
cg.drawLinearGradient(gradient,
                      start: CGPoint(x: 0, y: CGFloat(size)),
                      end:   CGPoint(x: CGFloat(size), y: 0),
                      options: [])

// ── Drawing the ground line ───────────────────────────────────────────────
cg.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.25])!)
let groundW = CGFloat(size) * 0.6
let groundH = CGFloat(size) * 0.08
let groundX = (CGFloat(size) - groundW) / 2
let groundY = CGFloat(size) * 0.20
let groundRect = CGRect(x: groundX, y: groundY, width: groundW, height: groundH)
let groundPath = CGPath(roundedRect: groundRect, cornerWidth: groundH / 2, cornerHeight: groundH / 2, transform: nil)
cg.addPath(groundPath)
cg.fillPath()

// ── Drawing the upward arrow defying gravity ────────────────────────────────
cg.setStrokeColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.95])!)
cg.setLineWidth(CGFloat(size) * 0.09)
cg.setLineCap(.round)
cg.setLineJoin(.round)

let centerX = CGFloat(size) / 2
let arrowStartY = CGFloat(size) * 0.38
let arrowEndY = CGFloat(size) * 0.80
let arrowHeadOffset = CGFloat(size) * 0.16

// Shaft
cg.move(to: CGPoint(x: centerX, y: arrowStartY))
cg.addLine(to: CGPoint(x: centerX, y: arrowEndY))

// Left arrowhead wing
cg.move(to: CGPoint(x: centerX - arrowHeadOffset, y: arrowEndY - arrowHeadOffset))
cg.addLine(to: CGPoint(x: centerX, y: arrowEndY))

// Right arrowhead wing
cg.addLine(to: CGPoint(x: centerX + arrowHeadOffset, y: arrowEndY - arrowHeadOffset))

cg.strokePath()

// ── Write PNG ──────────────────────────────────────────────────────────────
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("Failed to encode PNG"); exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outPath))
    print("Icon written to \(outPath)")
} catch {
    print("Error writing file: \(error)"); exit(1)
}
