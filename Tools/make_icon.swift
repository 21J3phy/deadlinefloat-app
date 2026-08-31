#!/usr/bin/env swift
//
//  Draws DeadlineFloat's app icon at every size macOS asks for.
//
//      swift Tools/make_icon.swift DeadlineFloat/Assets.xcassets/AppIcon.appiconset
//
import AppKit
import CoreGraphics
import Foundation

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// macOS icons are a squircle inset inside the canvas.
func squirclePath(in rect: CGRect) -> CGPath {
    let radius = rect.width * 0.2237
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.0664
    let body = canvas.insetBy(dx: inset, dy: inset)
    let path = squirclePath(in: body)

    context.saveGState()
    context.addPath(path)
    context.clip()

    // Deep indigo to violet, top-left to bottom-right.
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(srgbRed: 0.243, green: 0.278, blue: 0.788, alpha: 1),
            CGColor(srgbRed: 0.451, green: 0.243, blue: 0.831, alpha: 1),
            CGColor(srgbRed: 0.145, green: 0.176, blue: 0.451, alpha: 1)
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )

    // Specular sweep across the top third, the way light falls on glass.
    let sheen = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.34),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.midY),
        options: []
    )
    context.restoreGState()

    // The hourglass mark, drawn from the system symbol so it matches the app.
    let glyphSide = size * 0.46
    let glyphRect = CGRect(
        x: (size - glyphSide) / 2,
        y: (size - glyphSide) / 2,
        width: glyphSide,
        height: glyphSide
    )
    let configuration = NSImage.SymbolConfiguration(pointSize: glyphSide, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            NSColor.white.set()
            rect.fill()
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        var proposed = CGRect(origin: .zero, size: tinted.size)
        if let cgSymbol = tinted.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
            let aspect = CGFloat(cgSymbol.width) / CGFloat(cgSymbol.height)
            var target = glyphRect
            if aspect > 1 {
                target.size.height = glyphRect.width / aspect
                target.origin.y = (size - target.height) / 2
            } else {
                target.size.width = glyphRect.height * aspect
                target.origin.x = (size - target.width) / 2
            }
            context.setShadow(offset: CGSize(width: 0, height: -size * 0.006), blur: size * 0.02,
                              color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
            context.draw(cgSymbol, in: target)
            context.setShadow(offset: .zero, blur: 0, color: nil)
        }
    }

    // Hairline rim, so the icon reads as a physical object.
    context.addPath(squirclePath(in: body.insetBy(dx: size * 0.004, dy: size * 0.004)))
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
    context.setLineWidth(max(1, size * 0.007))
    context.strokePath()

    return context.makeImage()
}

struct Entry {
    let idiom = "mac"
    let size: Int
    let scale: Int
    var pixels: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
}

let entries = [16, 32, 128, 256, 512].flatMap { size in
    [Entry(size: size, scale: 1), Entry(size: size, scale: 2)]
}

for entry in entries {
    guard let image = draw(size: CGFloat(entry.pixels)) else {
        FileHandle.standardError.write(Data("Failed to draw \(entry.filename)\n".utf8))
        continue
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: outputDirectory.appendingPathComponent(entry.filename))
}

var images: [[String: String]] = []
for entry in entries {
    images.append([
        "idiom": entry.idiom,
        "size": "\(entry.size)x\(entry.size)",
        "scale": "\(entry.scale)x",
        "filename": entry.filename
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))

print("Wrote \(entries.count) icon images to \(outputDirectory.path)")
