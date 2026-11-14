// make-icon.swift: regenerates viewMD's app icon.
//
// Usage (from the repo root):
//   swift tools/make-icon.swift /tmp/icon.png
//   then resize into viewMD/Assets.xcassets/AppIcon.appiconset with `sips -z`
//   (16, 32, 128, 256 and 512 pt at 1x and 2x).
//
// The Markdown mark (M + down arrow) is by Dustin Curtis, dedicated to the
// public domain (CC0).

import AppKit

// Draws the viewMD icon at 1024×1024: Apple's macOS icon grid (an 824 pt
// rounded-rect body centered with a 100 pt margin) filled with a blue
// gradient, carrying the public-domain Markdown mark (M + down arrow) in
// white, with a soft drop shadow.
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185
let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let colors = [NSColor(srgbRed: 0.27, green: 0.56, blue: 1.00, alpha: 1).cgColor,
              NSColor(srgbRed: 0.16, green: 0.30, blue: 0.86, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
ctx.restoreGState()

// Markdown mark, scaled into the body. Original mark is 208×128 with a
// 15-unit stroke frame; here only the M and arrow are drawn, filled.
ctx.setFillColor(NSColor.white.cgColor)
let s: CGFloat = 3.3          // scale
let ox: CGFloat = 512 - 107.5 * s           // glyphs span x 30–185; center them
let oy: CGFloat = 512 - 64 * s             // bottom
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + (128 - y) * s) }
// "M": x 30–100, y 98 (bottom) to 30 (top), standard Markdown-mark geometry.
let m = CGMutablePath()
m.move(to: pt(30, 98)); m.addLine(to: pt(30, 30)); m.addLine(to: pt(50, 30)); m.addLine(to: pt(70, 55))
m.addLine(to: pt(90, 30)); m.addLine(to: pt(110, 30)); m.addLine(to: pt(110, 98)); m.addLine(to: pt(90, 98))
m.addLine(to: pt(90, 59)); m.addLine(to: pt(70, 84)); m.addLine(to: pt(50, 59)); m.addLine(to: pt(50, 98)); m.closeSubpath()
ctx.addPath(m); ctx.fillPath()
// Down arrow: x 125–185.
let a = CGMutablePath()
a.move(to: pt(155, 98)); a.addLine(to: pt(125, 65)); a.addLine(to: pt(145, 65)); a.addLine(to: pt(145, 30))
a.addLine(to: pt(165, 30)); a.addLine(to: pt(165, 65)); a.addLine(to: pt(185, 65)); a.closeSubpath()
ctx.addPath(a); ctx.fillPath()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
