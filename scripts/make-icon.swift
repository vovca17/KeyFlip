import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = output.deletingLastPathComponent().appendingPathComponent("Switcher.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.setFillColor(CGColor(red: 0.07, green: 0.12, blue: 0.20, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 200, cornerHeight: 200, transform: nil))
        context.fillPath()
        context.setStrokeColor(CGColor(red: 0.37, green: 0.90, blue: 0.79, alpha: 1))
        context.setLineWidth(70)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 275, y: 655)); context.addLine(to: CGPoint(x: 755, y: 655))
        context.move(to: CGPoint(x: 635, y: 775)); context.addLine(to: CGPoint(x: 755, y: 655)); context.addLine(to: CGPoint(x: 635, y: 535))
        context.move(to: CGPoint(x: 755, y: 365)); context.addLine(to: CGPoint(x: 275, y: 365))
        context.move(to: CGPoint(x: 395, y: 485)); context.addLine(to: CGPoint(x: 275, y: 365)); context.addLine(to: CGPoint(x: 395, y: 245))
        context.strokePath()
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        let url = folder.appendingPathComponent(name)
        let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(writer) else { fatalError("Cannot write icon") }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", folder.path, "-o", output.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at: folder)
