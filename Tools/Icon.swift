import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("M6Bar.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        NSColor(calibratedRed: 0.055, green: 0.09, blue: 0.085, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 218, yRadius: 218).fill()
        let shell = NSBezierPath(roundedRect: NSRect(x: 305, y: 180, width: 414, height: 670), xRadius: 205, yRadius: 205)
        NSColor(calibratedWhite: 0.17, alpha: 1).setFill(); shell.fill()
        NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.69, alpha: 1).setStroke()
        shell.lineWidth = 14; shell.stroke()
        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: 512, y: 850)); seam.line(to: NSPoint(x: 512, y: 590))
        seam.move(to: NSPoint(x: 310, y: 575)); seam.line(to: NSPoint(x: 714, y: 575))
        NSColor(calibratedWhite: 0.5, alpha: 0.4).setStroke(); seam.lineWidth = 8; seam.stroke()
        NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.69, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 488, y: 650, width: 48, height: 112), xRadius: 24, yRadius: 24).fill()
        for index in 0..<5 {
            let rect = NSRect(x: 377 + index * 56, y: 335, width: 35, height: 85)
            (index < 4 ? NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.69, alpha: 1) : NSColor(calibratedWhite: 0.4, alpha: 0.4)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let source = NSBitmapImageRep(data: tiff),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Icon bitmap unavailable") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSImage(cgImage: source.cgImage!, size: NSSize(width: 1024, height: 1024)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
