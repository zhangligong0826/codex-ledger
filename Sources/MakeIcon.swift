import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
func gradient(_ colors: [NSColor], path: NSBezierPath, angle: CGFloat) { NSGradient(colors: colors)!.draw(in: path, angle: angle) }
func shadow(_ blur: CGFloat, _ offset: NSSize, _ color: NSColor) {
    let shadow = NSShadow(); shadow.shadowBlurRadius = blur; shadow.shadowOffset = offset; shadow.shadowColor = color; shadow.set()
}
for (name, size) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
    let plate = NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 192, yRadius: 192)
    NSGraphicsContext.saveGraphicsState()
    shadow(24, NSSize(width: 0, height: -15), color(0.24, 0.38, 0.56, 0.22))
    color(0.90, 0.94, 0.98).setFill(); plate.fill(); NSGraphicsContext.restoreGraphicsState()
    gradient([color(0.75,0.85,0.94), color(0.92,0.96,0.99), color(0.99,1,1)], path: plate, angle: 68)
    NSGraphicsContext.saveGraphicsState(); plate.addClip()
    let mist = NSBezierPath(ovalIn: NSRect(x: 150, y: 320, width: 940, height: 810))
    gradient([color(1,1,1,0), color(1,1,1,0.65)], path: mist, angle: 90)
    NSGraphicsContext.restoreGraphicsState()
    plate.lineWidth = 3; color(1,1,1,0.8).setStroke(); plate.stroke()
    let rim = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 188, yRadius: 188)
    rim.lineWidth = 2; color(0.53,0.69,0.86,0.20).setStroke(); rim.stroke()
    for (index, height) in [240.0, 390.0, 540.0].enumerated() {
        let x = 252.0 + Double(index) * 190, y = 236.0
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 140, height: height), xRadius: 40, yRadius: 40)
        NSGraphicsContext.saveGraphicsState()
        shadow(22, NSSize(width: 6, height: -18), color(0.24,0.42,0.67,0.28))
        color(0.47,0.70,0.91).setFill(); bar.fill(); NSGraphicsContext.restoreGraphicsState()
        gradient([color(0.30,0.53,0.78), color(0.56,0.78,0.97), color(0.86,0.96,1), color(0.46,0.70,0.91)], path: bar, angle: 18)
        NSGraphicsContext.saveGraphicsState(); bar.addClip()
        let face = NSBezierPath(roundedRect: NSRect(x: x+10, y: y+10, width: 119, height: height-18), xRadius: 34, yRadius: 34)
        gradient([color(0.61,0.83,1,0.15), color(0.98,1,1,0.8)], path: face, angle: 90)
        let edge = NSBezierPath(roundedRect: NSRect(x: x+10, y: y+18, width: 12, height: height-33), xRadius: 6, yRadius: 6)
        gradient([color(1,1,1,0.08), color(1,1,1,0.92)], path: edge, angle: 90)
        let light = NSBezierPath(ovalIn: NSRect(x: x-10, y: y+height-68, width: 150, height: 110))
        gradient([color(1,1,1,0), color(1,1,1,0.75)], path: light, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        bar.lineWidth = 3; color(1,1,1,0.78).setStroke(); bar.stroke()
        let bevel = NSBezierPath(roundedRect: NSRect(x: x+5, y: y+5, width: 130, height: height-10), xRadius: 36, yRadius: 36)
        bevel.lineWidth = 2; color(0.32,0.56,0.81,0.24).setStroke(); bevel.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
