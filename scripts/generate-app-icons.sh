#!/bin/sh
# Rasterize app/icons/harbour-helmsman.svg to the launcher PNG sizes.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/app/icons/harbour-helmsman.svg"
swift - "$SVG" "$ROOT/app/icons" <<'EOF'
import AppKit

let args = CommandLine.arguments
let svg = URL(fileURLWithPath: args[1])
let icons = URL(fileURLWithPath: args[2])

func render(pixels: Int, dest: URL) throws {
    guard let img = NSImage(contentsOf: svg) else {
        fputs("failed to load \(svg.path)\n", stderr)
        exit(1)
    }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("failed to create bitmap\n", stderr)
        exit(1)
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fputs("failed to create graphics context\n", stderr)
        exit(1)
    }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    img.draw(
        in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)),
        from: NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height),
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to encode PNG\n", stderr)
        exit(1)
    }
    try png.write(to: dest)
    print("wrote \(dest.path)")
}

for size in [86, 108, 128, 172] {
    let dest = icons.appendingPathComponent("\(size)x\(size)/harbour-helmsman.png")
    try render(pixels: size, dest: dest)
}
EOF
chmod a-x "$ROOT"/app/icons/*/harbour-helmsman.png
