// Turns square artwork into the macOS app icon.
// Usage: swift Scripts/make-icon.swift Support/AppIcon-source.png Support/Kyo.icns
//
// macOS icons are a rounded square of 824pt inside a 1024pt canvas, with a soft
// shadow. Artwork should be full bleed with square corners; this adds the shape.
import AppKit
import SwiftUI

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source.png> <output.icns>\n".utf8))
    exit(64)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let artwork = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
else {
    FileHandle.standardError.write(Data("could not read \(sourceURL.path)\n".utf8))
    exit(66)
}

func render(canvas: Int) -> CGImage {
    let scale = CGFloat(canvas) / 1024
    let context = CGContext(
        data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        .applying(CGAffineTransform(scaleX: scale, y: scale))
    let outline = RoundedRectangle(cornerRadius: 185.4 * scale, style: .continuous)
        .path(in: body).cgPath

    // Shadow under the shape.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale,
        color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(outline)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.addPath(outline)
    context.clip()
    context.draw(artwork, in: body)
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Kyo-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// Each size is drawn from the artwork directly, so small ones stay sharp.
for points in [16, 32, 128, 256, 512] {
    write(render(canvas: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    write(
        render(canvas: points * 2),
        to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("Wrote \(outputURL.path)")
