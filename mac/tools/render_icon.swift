#!/usr/bin/env swift
// Renders ui/icon.svg into Icon/AppIcon.iconset with real transparency.
// The artwork is 824 x 824 on a 1024 x 1024 canvas, centered, which is the
// margin Apple's macOS icon grid leaves. Run from anywhere:
//   swift mac/tools/render_icon.swift
import AppKit

let tools = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
let mac = tools.deletingLastPathComponent()
let svg = mac.deletingLastPathComponent().appending(path: "ui/icon.svg")
let out = mac.appending(path: "Icon/AppIcon.iconset")
guard let image = NSImage(contentsOf: svg) else { fatalError("Could not read \(svg.path)") }
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill(using: .copy)
    let side = Double(pixels) * 824 / 1024
    let inset = (Double(pixels) - side) / 2
    image.draw(in: NSRect(x: inset, y: inset, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: out.appending(path: "icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: out.appending(path: "icon_\(size)x\(size)@2x.png"))
}
print("wrote 10 PNGs to \(out.path)")
