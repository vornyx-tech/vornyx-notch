//
//  make_icon.swift
//  Vornyx Notch
//
//  Turns a picture of an icon into an icon: trims the backdrop it was exported
//  on, and cuts it to the rounded-rect shape macOS draws app icons in.
//
//  Usage:  swift Configuration/make_icon.swift <image> <output.png> [size]
//
//  The shape sits on macOS's own grid: 824 points of a 1024-point canvas, the
//  margin left for the shadow. Every system icon measures exactly that, and an
//  icon drawn edge to edge instead stands a fifth taller than its neighbours in
//  the Dock.
//

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <image> <output.png> [size]\n".utf8))
    exit(1)
}
let size = args.count > 3 ? Int(args[3]) ?? 1024 : 1024

guard let data = FileManager.default.contents(atPath: args[1]),
      let rep = NSBitmapImageRep(data: data),
      let source = rep.cgImage
else {
    FileHandle.standardError.write(Data("could not read \(args[1])\n".utf8))
    exit(1)
}

/// The picture's own edges, with any flat backdrop it was exported on removed.
///
/// The backdrop is whatever colour the four corners agree on; if they do not
/// agree there is nothing to trim. What is left is squared up around its own
/// centre, because an icon is square and a soft glow reaches further sideways
/// than the icon itself does.
func artworkBounds(_ rep: NSBitmapImageRep) -> CGRect {
    let w = rep.pixelsWide, h = rep.pixelsHigh
    func rgb(_ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat)? {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }
    let corners = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)].compactMap { rgb($0.0, $0.1) }
    guard corners.count == 4 else { return CGRect(x: 0, y: 0, width: w, height: h) }
    func apart(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
    }
    let backdrop = corners[0]
    guard corners.dropFirst().allSatisfy({ apart($0, backdrop) < 0.05 }) else {
        return CGRect(x: 0, y: 0, width: w, height: h)
    }
    func isBackdrop(_ x: Int, _ y: Int) -> Bool {
        guard let p = rgb(x, y) else { return true }
        return apart(p, backdrop) < 0.05
    }
    // Scanned along the middle, where the artwork is at its widest and tallest
    // - a corner curve would report the shape's inset rather than its edge.
    var left = 0, right = w - 1, top = 0, bottom = h - 1
    while left < w / 2, isBackdrop(left, h / 2) { left += 1 }
    while right > w / 2, isBackdrop(right, h / 2) { right -= 1 }
    while top < h / 2, isBackdrop(w / 2, top) { top += 1 }
    while bottom > h / 2, isBackdrop(w / 2, bottom) { bottom -= 1 }
    guard right > left, bottom > top else { return CGRect(x: 0, y: 0, width: w, height: h) }

    let side = min(CGFloat(right - left + 1), CGFloat(bottom - top + 1))
    let midX = CGFloat(left + right) / 2, midY = CGFloat(top + bottom) / 2
    return CGRect(x: midX - side / 2, y: midY - side / 2, width: side, height: side)
}

let bounds = artworkBounds(rep)
guard let art = source.cropping(to: bounds) else {
    FileHandle.standardError.write(Data("could not crop the artwork\n".utf8))
    exit(1)
}

let canvas = CGFloat(size)
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }
ctx.interpolationQuality = .high

let side = canvas * 824 / 1024
let margin = (canvas - side) / 2
let rect = CGRect(x: margin, y: margin, width: side, height: side)
// Apple's corner: a little under a quarter of the side.
let radius = side * 0.2237
let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// The shadow the margin is there for.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.01),
              blur: canvas * 0.023,
              color: CGColor(gray: 0, alpha: 0.3))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
// Half a point out, so the shape's edge is artwork rather than the seam
// between the artwork and nothing.
ctx.draw(art, in: rect.insetBy(dx: -0.5, dy: -0.5))
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
print("artwork \(Int(bounds.width))x\(Int(bounds.height)) at (\(Int(bounds.minX)), \(Int(bounds.minY))) -> \(args[2]) at \(size)px")
