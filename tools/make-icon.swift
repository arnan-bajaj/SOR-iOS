import AppKit
// The app icon: the team's gear-and-S emblem, white on the board's dark slate, with the S in team red.
let size = 1024.0
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
// Background: slate, a little lighter at the top
let bg = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.16, green: 0.19, blue: 0.21, alpha: 1), CGColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
// Gear: 12 teeth
let c = CGPoint(x: size / 2, y: size / 2)
let teeth = 12, rOut = 372.0, rIn = 306.0
let path = CGMutablePath()
for i in 0..<(teeth * 2) {
    let a0 = Double(i) / Double(teeth * 2) * 2 * .pi - .pi / 2
    let a1 = Double(i + 1) / Double(teeth * 2) * 2 * .pi - .pi / 2
    let r = i % 2 == 0 ? rOut : rIn
    // taper the teeth a little
    let inset = i % 2 == 0 ? 0.045 : 0.0
    let p0 = CGPoint(x: c.x + r * cos(a0 + inset), y: c.y + r * sin(a0 + inset))
    let p1 = CGPoint(x: c.x + r * cos(a1 - inset), y: c.y + r * sin(a1 - inset))
    if i == 0 { path.move(to: p0) } else { path.addLine(to: p0) }
    path.addLine(to: p1)
}
path.closeSubpath()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.5))
ctx.addPath(path)
ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// Inner ring in slate, then a white disc for the S
ctx.setFillColor(CGColor(red: 0.11, green: 0.13, blue: 0.15, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - 244, y: c.y - 244, width: 488, height: 488))
ctx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - 208, y: c.y - 208, width: 416, height: 416))
// The S
let font = NSFont.systemFont(ofSize: 330, weight: .black)
let para = NSMutableParagraphStyle(); para.alignment = .center
let s = NSAttributedString(string: "S", attributes: [.font: font, .foregroundColor: NSColor(red: 0.78, green: 0.04, blue: 0.04, alpha: 1), .paragraphStyle: para])
let b = s.boundingRect(with: NSSize(width: size, height: size), options: [.usesLineFragmentOrigin])
s.draw(in: CGRect(x: 0, y: c.y - b.height / 2 + 8, width: size, height: b.height))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
