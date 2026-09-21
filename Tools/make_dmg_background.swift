#!/usr/bin/env swift
//
//  Draws the backdrop of the disk image window, in the same indigo-to-violet
//  the app icon uses, so the installer looks like the app it installs.
//
//      swift Tools/make_dmg_background.swift build/dmg-background
//
//  Writes background.png (1x) and background@2x.png; Tools/make_dmg.sh folds the
//  two into one multi-representation TIFF, which is what the Finder needs to
//  draw a disk image backdrop sharply on a Retina display.
//
import AppKit
import CoreGraphics
import Foundation

/// The Finder window the disk image opens at, in points. Tools/make_dmg.sh
/// positions the two icons against these same numbers.
///
/// The backdrop is drawn taller than the window on purpose. The Finder pins a
/// background picture to the top left of the window's *content* area and does
/// not scale it, and the chrome above that area is a different height on every
/// macOS — about 28 points through macOS 15, about 70 on macOS 26, which shows
/// the path as well as the title. A backdrop shorter than the content area
/// leaves a bare white or grey band along the bottom; a taller one is merely
/// cropped. So it is drawn long, and everything that matters is kept inside
/// `safeHeight`, which is what is visible even under the tallest chrome.
let windowWidth: CGFloat = 660
let windowHeight: CGFloat = 420
let backdropHeight: CGFloat = 520
let safeHeight: CGFloat = 350
let iconBaseline: CGFloat = 200   // centre of both icons, measured from the top
let appIconCentreX: CGFloat = 175
let applicationsCentreX: CGFloat = 485

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// Core Graphics puts the origin at the bottom left; every measurement above is
/// from the top, the way the Finder states icon positions.
func fromTop(_ y: CGFloat) -> CGFloat { backdropHeight - y }

func drawText(
    _ string: String,
    in context: CGContext,
    centredAt centre: CGPoint,
    size: CGFloat,
    weight: NSFont.Weight,
    colour: NSColor,
    tracking: CGFloat = 0
) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: colour,
        .kern: tracking
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: centre.x - bounds.width / 2 - bounds.origin.x,
        y: centre.y - bounds.height / 2 - bounds.origin.y
    )
    CTLineDraw(line, context)
}

func draw(scale: CGFloat) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: Int(windowWidth * scale),
        height: Int(backdropHeight * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.scaleBy(x: scale, y: scale)
    let canvas = CGRect(x: 0, y: 0, width: windowWidth, height: backdropHeight)

    // The icon's gradient, darkened, so white type and the icons sit on top of
    // it comfortably and the window does not glare in a dark room.
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            srgb(0.106, 0.122, 0.325),
            srgb(0.184, 0.106, 0.341),
            srgb(0.063, 0.075, 0.196)
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvas.minX, y: canvas.maxY),
        end: CGPoint(x: canvas.maxX, y: canvas.minY),
        options: []
    )

    // A soft glow behind each icon well, so the icons look seated rather than
    // pasted on.
    for centreX in [appIconCentreX, applicationsCentreX] {
        let centre = CGPoint(x: centreX, y: fromTop(iconBaseline))
        let glow = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [srgb(1, 1, 1, 0.10), srgb(1, 1, 1, 0)] as CFArray,
            locations: [0, 1]
        )!
        context.drawRadialGradient(
            glow,
            startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: 118,
            options: []
        )
    }

    // The arrow from the app to the Applications folder: the whole instruction,
    // without a sentence.
    let arrowY = fromTop(iconBaseline)
    let arrowStart = appIconCentreX + 86
    let arrowEnd = applicationsCentreX - 86
    let head: CGFloat = 13
    context.setStrokeColor(srgb(1, 1, 1, 0.38))
    context.setLineWidth(2)
    context.setLineCap(.round)
    context.setLineDash(phase: 0, lengths: [7, 7])
    context.move(to: CGPoint(x: arrowStart, y: arrowY))
    context.addLine(to: CGPoint(x: arrowEnd - head, y: arrowY))
    context.strokePath()

    context.setLineDash(phase: 0, lengths: [])
    context.setFillColor(srgb(1, 1, 1, 0.5))
    context.move(to: CGPoint(x: arrowEnd, y: arrowY))
    context.addLine(to: CGPoint(x: arrowEnd - head, y: arrowY + head * 0.62))
    context.addLine(to: CGPoint(x: arrowEnd - head, y: arrowY - head * 0.62))
    context.closePath()
    context.fillPath()

    drawText(
        "DeadlineFloat",
        in: context,
        centredAt: CGPoint(x: windowWidth / 2, y: fromTop(58)),
        size: 30,
        weight: .semibold,
        colour: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96),
        tracking: 0.4
    )
    drawText(
        "Drag the app into Applications",
        in: context,
        centredAt: CGPoint(x: windowWidth / 2, y: fromTop(88)),
        size: 13,
        weight: .regular,
        colour: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.62)
    )
    // Launch at Login only works from /Applications, which is worth saying once
    // where someone will actually read it.
    drawText(
        "Launch at Login needs it there",
        in: context,
        centredAt: CGPoint(x: windowWidth / 2, y: fromTop(safeHeight - 24)),
        size: 11,
        weight: .regular,
        colour: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.38)
    )

    return context.makeImage()
}

for scale in [CGFloat(1), CGFloat(2)] {
    guard let image = draw(scale: scale) else {
        FileHandle.standardError.write(Data("Failed to draw the backdrop at \(Int(scale))x\n".utf8))
        exit(1)
    }
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: windowWidth, height: backdropHeight)
    guard let data = representation.representation(using: .png, properties: [:]) else { exit(1) }
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try data.write(to: outputDirectory.appendingPathComponent(name))
}

print("Wrote the disk image backdrop to \(outputDirectory.path)")
