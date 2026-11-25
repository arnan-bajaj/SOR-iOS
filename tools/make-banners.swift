import AppKit
// App Store "Header" (21:9, 3840×1646) and "Search results" (3:2, 3840×2560) images, drawn from the demo screenshots.
//   swift tools/make-banners.swift AppStore
let dir = CommandLine.arguments[1]
let shots = ["1-home", "4-signups", "5-timeline", "2-board", "7-analytics"].compactMap { NSImage(contentsOfFile: "\(dir)/screenshots/\($0).png") }
let logo = NSImage(contentsOfFile: "\(dir)/../SOR/Resources/Assets.xcassets/Logo.imageset/Logo.png")!
let cs = CGColorSpaceCreateDeviceRGB()

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!)
}

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    ctx.setFillColor(CGColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (x, y, r, c) in [(0.1, 0.9, 0.9, CGColor(red: 0.18, green: 0.56, blue: 1, alpha: 0.30)),
                         (0.95, 0.6, 0.7, CGColor(red: 0.86, green: 0.13, blue: 0.16, alpha: 0.26)),
                         (0.35, 0.0, 0.8, CGColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.26))] {
        let g = CGGradient(colorsSpace: cs, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w * x, y: h * y), startRadius: 0, endCenter: CGPoint(x: w * x, y: h * y), endRadius: max(w, h) * r, options: [])
    }
}

func phone(_ ctx: CGContext, _ img: NSImage, center: CGPoint, height: CGFloat, angle: CGFloat) {
    let w = height * img.size.width / img.size.height
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -w / 2, y: -height / 2, width: w, height: height)
    let radius = w * 0.13
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.02), blur: height * 0.06, color: CGColor(gray: 0, alpha: 0.6))
    let frame = CGPath(roundedRect: r.insetBy(dx: -w * 0.025, dy: -w * 0.025), cornerWidth: radius * 1.15, cornerHeight: radius * 1.15, transform: nil)
    ctx.addPath(frame); ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
    img.draw(in: r)
    ctx.restoreGState()
}

func attributed(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    return NSAttributedString(string: s, attributes: [.font: rounded, .foregroundColor: color, .paragraphStyle: para])
}

/// Draws a text block whose top edge sits at `top` (y grows upward) and returns its bottom edge.
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
    let a = attributed(s, size: size, weight: weight, color: color)
    let h = ceil(a.boundingRect(with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin]).height)
    a.draw(with: CGRect(x: x, y: top - h, width: width, height: h), options: [.usesLineFragmentOrigin])
    return top - h
}

/// Logo, name and one line about the app, as a block whose top is `top`. Returns the block's height.
@discardableResult
func brand(_ ctx: CGContext, x: CGFloat, top: CGFloat, logo size: CGFloat, title: CGFloat, sub: CGFloat, width: CGFloat) -> CGFloat {
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: x, y: top - size, width: size, height: size)); ctx.clip()
    logo.draw(in: CGRect(x: x, y: top - size, width: size, height: size))
    ctx.restoreGState()
    let t = text("SOR Team Board", size: title, weight: .heavy, color: .white, x: x, top: top - size - title * 0.35, width: width)
    let b = text("Tasks, meetings and check-ins for FRC Team 6059 System Overload.", size: sub, weight: .medium,
                 color: NSColor(white: 1, alpha: 0.75), x: x, top: t - sub * 0.45, width: width)
    return top - b
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
}

// Header: 21:9. The App Store crops it to about 3:2 on iPhone (centered) and puts the back and share buttons over the
// top, so the words and the main phone sit in the middle 60% and below the top fifth; the outer edges are only background.
save(canvas(3840, 1646) { ctx in
    background(ctx, 3840, 1646)
    phone(ctx, shots[1], center: CGPoint(x: 3130, y: 700), height: 1380, angle: 5)
    phone(ctx, shots[0], center: CGPoint(x: 2470, y: 760), height: 1560, angle: 0)
    brand(ctx, x: 760, top: 1646 - 420, logo: 190, title: 140, sub: 64, width: 1180)
}, "header.png")

// Search results: 3:2. The search card shows it wider than 3:2, keeping the top part, so the words and the phones'
// screens sit in the top half; the phones run off the bottom edge on purpose.
save(canvas(3840, 2560) { ctx in
    background(ctx, 3840, 2560)
    phone(ctx, shots[3], center: CGPoint(x: 3360, y: 1180), height: 2250, angle: 4)
    phone(ctx, shots[0], center: CGPoint(x: 2560, y: 1250), height: 2400, angle: 0)
    brand(ctx, x: 260, top: 2560 - 250, logo: 260, title: 190, sub: 92, width: 1650)
}, "search-results.png")
print("done")
