#!/usr/bin/env swift
//
// generate_icons.swift
//
// Renders the halfFull app icon set: an "aA" wordmark on an off-white
// "paper" squircle with deep-black letters. Editorial feel — fits a
// product whose whole job is making text right.
//
// Run after editing the design constants below:
//
//     swiftc -framework AppKit -framework CoreText -o /tmp/gen Scripts/generate_icons.swift
//     /tmp/gen
//
// Output: Assets.xcassets/AppIcon.appiconset/icon_<size>.png + Contents.json

import Foundation
import CoreGraphics
import CoreText
import AppKit

// MARK: - Design

/// Off-white "paper" background with a very subtle top-to-bottom gradient
/// so the surface isn't sterile flat at 1024 px.
let backingTop    = CGColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)  // pure white
let backingBottom = CGColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1.0)  // soft grey

/// Letters: deep near-black, slight warm hint.
let glyphColor    = CGColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)

/// macOS app icons use a continuous "squircle" — Apple's bundle radius is ~22.37% of edge.
let cornerRadiusRatio: CGFloat = 0.2237
let masterSize: CGFloat = 1024
let outputDir = "Assets.xcassets/AppIcon.appiconset"

struct IconSpec { let size: Int; let scale: Int }
let specs: [IconSpec] = [
    .init(size: 16,  scale: 1), .init(size: 16,  scale: 2),
    .init(size: 32,  scale: 1), .init(size: 32,  scale: 2),
    .init(size: 128, scale: 1), .init(size: 128, scale: 2),
    .init(size: 256, scale: 1), .init(size: 256, scale: 2),
    .init(size: 512, scale: 1), .init(size: 512, scale: 2),
]

// MARK: - Rendering

func renderMaster() -> CGImage {
    let side = Int(masterSize)
    let cs = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil,
                              width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: bitmapInfo) else {
        fatalError("CGContext failed")
    }

    let rect = CGRect(x: 0, y: 0, width: masterSize, height: masterSize)
    let radius = masterSize * cornerRadiusRatio

    // 1. Clip everything to the squircle silhouette.
    ctx.saveGState()
    let squirclePath = CGPath(roundedRect: rect,
                              cornerWidth: radius, cornerHeight: radius,
                              transform: nil)
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Backing: subtle off-white vertical gradient.
    let backing = CGGradient(colorsSpace: cs,
                             colors: [backingTop, backingBottom] as CFArray,
                             locations: [0.0, 1.0])!
    ctx.drawLinearGradient(backing,
                           start: CGPoint(x: 0, y: masterSize),
                           end:   CGPoint(x: 0, y: 0),
                           options: [])

    // 3. Letterforms.
    drawAaMark(into: ctx, canvasSize: masterSize)

    ctx.restoreGState()

    return ctx.makeImage()!
}

func drawAaMark(into ctx: CGContext, canvasSize: CGFloat) {
    let bigSize: CGFloat   = canvasSize * 0.62
    let smallSize: CGFloat = canvasSize * 0.40

    let bigFont   = NSFont.systemFont(ofSize: bigSize,   weight: .heavy) as CTFont
    let smallFont = NSFont.systemFont(ofSize: smallSize, weight: .heavy) as CTFont
    let color = NSColor(cgColor: glyphColor)!

    // Small "a" on the LEFT, big "A" on the RIGHT — same baseline. Matches the
    // SF Symbol `textformat.size` rendering shown in the menu bar.
    let attra = NSAttributedString(string: "a", attributes: [
        .font: smallFont, .foregroundColor: color
    ])
    let attrA = NSAttributedString(string: "A", attributes: [
        .font: bigFont,   .foregroundColor: color
    ])

    let linea = CTLineCreateWithAttributedString(attra)
    let lineA = CTLineCreateWithAttributedString(attrA)

    var ascentA: CGFloat = 0, descentA: CGFloat = 0, leadingA: CGFloat = 0
    let widthA = CGFloat(CTLineGetTypographicBounds(lineA, &ascentA, &descentA, &leadingA))
    var ascenta: CGFloat = 0, descenta: CGFloat = 0, leadinga: CGFloat = 0
    let widtha = CGFloat(CTLineGetTypographicBounds(linea, &ascenta, &descenta, &leadinga))

    let kerning = canvasSize * 0.02
    let totalWidth = widtha + kerning + widthA
    let originX = (canvasSize - totalWidth) / 2

    let totalHeight = ascentA + descentA
    let baseline = (canvasSize - totalHeight) / 2 + descentA + canvasSize * 0.02

    ctx.textPosition = CGPoint(x: originX, y: baseline)
    CTLineDraw(linea, ctx)

    ctx.textPosition = CGPoint(x: originX + widtha + kerning, y: baseline)
    CTLineDraw(lineA, ctx)
}

func downsample(_ master: CGImage, toEdge px: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed for \(path)")
    }
    try data.write(to: url)
}

func writeContentsJSON(_ specs: [IconSpec], at path: String) throws {
    struct Entry: Encodable {
        let idiom = "mac"
        let size: String
        let scale: String
        let filename: String
    }
    struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    struct Manifest: Encodable {
        let images: [Entry]
        enum CodingKeys: String, CodingKey { case images, info }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(images, forKey: .images)
            var infoC = c.nestedContainer(keyedBy: DynamicKey.self, forKey: .info)
            try infoC.encode(1, forKey: DynamicKey(stringValue: "version")!)
            try infoC.encode("xcode", forKey: DynamicKey(stringValue: "author")!)
        }
    }
    let entries = specs.map {
        Entry(size: "\($0.size)x\($0.size)",
              scale: "\($0.scale)x",
              filename: filename(for: $0))
    }
    let manifest = Manifest(images: entries)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try enc.encode(manifest)
    try data.write(to: URL(fileURLWithPath: path))
}

func filename(for spec: IconSpec) -> String {
    "icon_\(spec.size)x\(spec.size)@\(spec.scale)x.png"
}

// MARK: - Main

let cwd = FileManager.default.currentDirectoryPath
let outPath = cwd + "/" + outputDir
try? FileManager.default.createDirectory(atPath: outPath, withIntermediateDirectories: true)

print("Rendering master 1024x1024…")
let master = renderMaster()

for spec in specs {
    let px = spec.size * spec.scale
    let image: CGImage = (px == Int(masterSize)) ? master : downsample(master, toEdge: px)
    let filePath = outPath + "/" + filename(for: spec)
    try writePNG(image, to: filePath)
    print("  → \(filename(for: spec)) (\(px)×\(px))")
}

try writeContentsJSON(specs, at: outPath + "/Contents.json")
print("Wrote Contents.json")
print("Done.")
