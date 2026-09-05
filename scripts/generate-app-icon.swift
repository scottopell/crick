// Run from the repository root:
// swiftc scripts/generate-app-icon.swift -o /tmp/crick-icon && /tmp/crick-icon
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Opaque, reproducible beta artwork: a creek bending around a river stone.
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
context.setFillColor(color(0.10, 0.27, 0.24))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
func creek(width: CGFloat, color: CGColor, offset: CGFloat = 0) {
    context.beginPath()
    context.move(to: CGPoint(x: 610 + offset, y: -100))
    context.addCurve(to: CGPoint(x: 380 + offset, y: 480),
                     control1: CGPoint(x: 120 + offset, y: 150),
                     control2: CGPoint(x: 220 + offset, y: 300))
    context.addCurve(to: CGPoint(x: 590 + offset, y: 1124),
                     control1: CGPoint(x: 850 + offset, y: 770),
                     control2: CGPoint(x: 810 + offset, y: 880))
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setStrokeColor(color)
    context.strokePath()
}
creek(width: 440, color: color(0.46, 0.57, 0.39))
creek(width: 340, color: color(0.19, 0.65, 0.72))
creek(width: 26, color: color(0.65, 0.88, 0.85), offset: -86)
context.setFillColor(color(0.18, 0.37, 0.36))
context.fillEllipse(in: CGRect(x: 397, y: 387, width: 240, height: 180))
context.setFillColor(color(0.77, 0.76, 0.64))
context.fillEllipse(in: CGRect(x: 399, y: 412, width: 228, height: 176))
context.setFillColor(color(0.89, 0.87, 0.75))
context.fillEllipse(in: CGRect(x: 427, y: 481, width: 161, height: 77))
let output = URL(fileURLWithPath: "Apps/CrickiOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
print(output.path)
