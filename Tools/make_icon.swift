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

func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
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

    // The mark is the product: the squircle is the screen, and the bar is down
    // its right edge — dark glass, flush with the bezel, rounded only on the
    // inner side, exactly as it sits on a real display. The day is drawn on it
    // as blocks of their Google colour, the red needle marks now, and the pill
    // that says what is on floats beside it.
    //
    // An earlier attempt drew the bar as a free-standing white stick with
    // coloured bands across it and a white tab on one side, which read as a
    // pregnancy test. Anchoring it to the edge and making it dark glass — which
    // is what the app actually draws — is what fixes that.
    //
    // Measured from the top, the way the interface is described, and converted
    // at the point of use because Core Graphics counts upward.
    func fromTop(_ fraction: CGFloat) -> CGFloat { size - size * fraction }

    context.saveGState()
    context.addPath(path)          // everything below is clipped to the screen
    context.clip()

    let barWidth = size * 0.125
    let barRight = body.maxX + size * 0.02   // past the edge; the clip trims it
    // Kept inside the squircle's straight flank: run it any further and the
    // rounded caps collide with the corner curve and leave a wedge.
    let barTop: CGFloat = 0.168
    let barBottom: CGFloat = 0.832
    let barRect = CGRect(
        x: barRight - barWidth,
        y: fromTop(barBottom),
        width: barWidth,
        height: size * (barBottom - barTop)
    )
    let radius = barWidth * 0.46
    let bar = CGPath(roundedRect: barRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.addPath(bar)
    context.setFillColor(CGColor(srgbRed: 0.055, green: 0.050, blue: 0.125, alpha: 0.94))
    context.fillPath()

    // The day's events, as far down the bar as they fall and as long as they
    // last — the same rule the real sliver draws by. Four, because a fifth is
    // indistinguishable at 32 points.
    struct Block { let from: CGFloat; let to: CGFloat; let colour: CGColor }
    let blocks = [
        Block(from: 0.075, to: 0.175, colour: srgb(0.28, 0.52, 0.96)),   // blueberry
        Block(from: 0.235, to: 0.345, colour: srgb(0.13, 0.70, 0.52)),   // basil
        Block(from: 0.430, to: 0.600, colour: srgb(0.98, 0.72, 0.22)),   // banana — the one on now
        Block(from: 0.700, to: 0.880, colour: srgb(0.92, 0.33, 0.37))    // tomato — the deadline
    ]

    context.saveGState()
    context.addPath(bar)
    context.clip()
    for block in blocks {
        context.setFillColor(block.colour)
        context.fill(CGRect(
            x: barRect.minX,
            y: barRect.maxY - barRect.height * block.to,
            width: barRect.width,
            height: barRect.height * (block.to - block.from)
        ))
    }
    context.restoreGState()

    // A hairline down the bar's inner side, the way glass catches light at an
    // edge, so it separates from the screen behind it.
    context.addPath(bar)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30))
    context.setLineWidth(max(0.75, size * 0.007))
    context.strokePath()

    // Now: the pill that floats beside the bar, and the needle through it.
    let nowFraction: CGFloat = 0.515        // of the bar's own height, from the top
    let needleY = barRect.maxY - barRect.height * nowFraction
    let pillHeight = size * 0.140
    let pillRect = CGRect(
        x: size * 0.150,
        y: needleY - pillHeight / 2,
        width: size * 0.375,
        height: pillHeight
    )
    let pillRadius = pillHeight * 0.38
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.026,
                      color: CGColor(srgbRed: 0.02, green: 0.01, blue: 0.08, alpha: 0.5))
    context.addPath(CGPath(roundedRect: pillRect, cornerWidth: pillRadius,
                           cornerHeight: pillRadius, transform: nil))
    context.setFillColor(CGColor(srgbRed: 0.055, green: 0.050, blue: 0.125, alpha: 0.94))
    context.fillPath()
    context.restoreGState()

    // Inside it: the event's colour, then its countdown as one bar of type.
    // Both vanish below about 32 points, which is the right thing to happen.
    let dot = CGRect(x: pillRect.minX + pillHeight * 0.34,
                     y: pillRect.midY - pillHeight * 0.16,
                     width: pillHeight * 0.32, height: pillHeight * 0.32)
    context.addPath(CGPath(roundedRect: dot, cornerWidth: dot.width * 0.34,
                           cornerHeight: dot.width * 0.34, transform: nil))
    context.setFillColor(srgb(0.98, 0.72, 0.22))
    context.fillPath()

    let textBar = CGRect(x: dot.maxX + pillHeight * 0.26, y: pillRect.midY - pillHeight * 0.075,
                         width: pillRect.width - (dot.maxX - pillRect.minX) - pillHeight * 0.62,
                         height: pillHeight * 0.15)
    context.addPath(CGPath(roundedRect: textBar, cornerWidth: textBar.height / 2,
                           cornerHeight: textBar.height / 2, transform: nil))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.68))
    context.fillPath()

    // The needle: from the pill, across the bar, level with the block it marks.
    let needleHeight = max(1, size * 0.021)
    let needleRect = CGRect(
        x: pillRect.maxX - size * 0.010,
        y: needleY - needleHeight / 2,
        width: barRect.maxX - (pillRect.maxX - size * 0.010),
        height: needleHeight
    )
    context.addPath(CGPath(roundedRect: needleRect, cornerWidth: needleHeight / 2,
                           cornerHeight: needleHeight / 2, transform: nil))
    context.setFillColor(srgb(0.96, 0.24, 0.26))
    context.fillPath()

    context.restoreGState()

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
