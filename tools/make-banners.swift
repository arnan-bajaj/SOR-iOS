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

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at p: CGPoint, width: CGFloat) {
    let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    NSAttributedString(string: s, attributes: [.font: rounded, .foregroundColor: color, .paragraphStyle: para])
        .draw(with: CGRect(x: p.x, y: p.y, width: width, height: size * 3), options: [.usesLineFragmentOrigin])
}

func brand(_ ctx: CGContext, x: CGFloat, top: CGFloat, scale: CGFloat, width: CGFloat) {
    let s = 220 * scale
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: x, y: top - s, width: s, height: s)); ctx.clip()
    logo.draw(in: CGRect(x: x, y: top - s, width: s, height: s))
    ctx.restoreGState()
    // text() draws from the top of a box 3 lines tall, so place each box's top just under what's above it
    let titleTop = top - s - 60 * scale
    text("SOR Team Board", size: 150 * scale, weight: .heavy, color: .white, at: CGPoint(x: x, y: titleTop - 450 * scale), width: width)
    let subTop = titleTop - 200 * scale
    text("Tasks, meetings and check-ins for FRC Team 6059 System Overload.", size: 64 * scale, weight: .medium,
         color: NSColor(white: 1, alpha: 0.72), at: CGPoint(x: x, y: subTop - 192 * scale), width: width)
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
}

// Header: 21:9, words on the left, three phones on the right
save(canvas(3840, 1646) { ctx in
    background(ctx, 3840, 1646)
    brand(ctx, x: 220, top: 1646 - 260, scale: 1, width: 1500)
    phone(ctx, shots[1], center: CGPoint(x: 2350, y: 760), height: 1500, angle: -4)
    phone(ctx, shots[2], center: CGPoint(x: 3420, y: 760), height: 1500, angle: 4)
    phone(ctx, shots[0], center: CGPoint(x: 2890, y: 800), height: 1640, angle: 0)
}, "header.png")

// Search results: 3:2, words on top, three phones below
save(canvas(3840, 2560) { ctx in
    background(ctx, 3840, 2560)
    brand(ctx, x: 260, top: 2560 - 170, scale: 0.85, width: 3300)
    phone(ctx, shots[3], center: CGPoint(x: 900, y: 760), height: 1450, angle: -3)
    phone(ctx, shots[4], center: CGPoint(x: 2940, y: 760), height: 1450, angle: 3)
    phone(ctx, shots[0], center: CGPoint(x: 1920, y: 800), height: 1580, angle: 0)
}, "search-results.png")
print("done")
