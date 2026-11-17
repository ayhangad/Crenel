// Draws the DMG window background ("notch dropping the icon", docs/DISTRIBUTION.md)
// at 1x and 2x. Usage: swift background.swift <output-dir> <version> <fonts-dir>
// Writes background.png and background@2x.png. Layout constants are shared with
// settings.py: content 440×480 points, app icon at (220, 132), Applications at (220, 356).
import AppKit
import CoreText

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write("usage: background.swift <output-dir> <version> <fonts-dir>\n".data(using: .utf8)!)
    exit(2)
}
let outputDir = URL(fileURLWithPath: arguments[1])
let version = arguments[2]
let fontsDir = URL(fileURLWithPath: arguments[3])
for name in ["Geist-Regular.ttf", "Geist-Medium.ttf"] {
    CTFontManagerRegisterFontsForURL(fontsDir.appending(path: name) as CFURL, .process, nil)
}

// The layout is 440×520, but the image is drawn much taller: Finder may open the window
// taller than asked (path and status bars follow the user's own Finder settings), and
// whatever the image does not cover shows white.
let layoutHeight: CGFloat = 480
let size = CGSize(width: 440, height: 1100)
let appCenter = CGPoint(x: 220, y: 132)
let applicationsCenter = CGPoint(x: 220, y: 356)
let teal = NSColor(srgbRed: 0x34 / 255, green: 0xE6 / 255, blue: 0xCB / 255, alpha: 1)
let tealCore = NSColor(srgbRed: 0xB9 / 255, green: 1, blue: 0xF3 / 255, alpha: 1)
let ink1 = NSColor(srgbRed: 0xF3 / 255, green: 0xF1 / 255, blue: 0xEC / 255, alpha: 1)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    // Top-left origin, like Finder's icon coordinates.
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)

    // Ground: near black, a faint diagonal, a 6 % dot grid.
    let ground = NSGradient(colors: [NSColor(white: 0.075, alpha: 1), NSColor(white: 0.03, alpha: 1)])!
    ground.draw(in: CGRect(origin: .zero, size: size), angle: -60)
    cg.setFillColor(NSColor(white: 1, alpha: 0.06).cgColor)
    stride(from: 10.0, to: size.width, by: 14).forEach { x in
        stride(from: 10.0, to: size.height, by: 14).forEach { y in
            cg.fillEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
        }
    }

    // The notch hanging from the top edge, with outward flares.
    let notch = CGMutablePath()
    let notchWidth: CGFloat = 176, notchHeight: CGFloat = 30, flare: CGFloat = 9, radius: CGFloat = 14
    let left = (size.width - notchWidth) / 2, right = left + notchWidth
    notch.move(to: CGPoint(x: left - flare, y: 0))
    notch.addQuadCurve(to: CGPoint(x: left, y: flare), control: CGPoint(x: left, y: 0))
    notch.addLine(to: CGPoint(x: left, y: notchHeight - radius))
    notch.addQuadCurve(to: CGPoint(x: left + radius, y: notchHeight), control: CGPoint(x: left, y: notchHeight))
    notch.addLine(to: CGPoint(x: right - radius, y: notchHeight))
    notch.addQuadCurve(to: CGPoint(x: right, y: notchHeight - radius), control: CGPoint(x: right, y: notchHeight))
    notch.addLine(to: CGPoint(x: right, y: flare))
    notch.addQuadCurve(to: CGPoint(x: right + flare, y: 0), control: CGPoint(x: right, y: 0))
    notch.closeSubpath()
    cg.addPath(notch)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.addPath(notch)
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
    cg.setLineWidth(0.75)
    cg.strokePath()

    // A soft glow under the notch, falling towards where the icon lands.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(white: 1, alpha: 0.06).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    cg.saveGState()
    cg.translateBy(x: size.width / 2, y: notchHeight)
    cg.scaleBy(x: 1.15, y: 1)
    cg.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 95, options: [])
    cg.restoreGState()

    // The lamp trail: ghost cells light up towards Applications.
    let cells: [(alpha: CGFloat, lit: Bool)] = [(0.08, false), (0.12, false), (0.35, false), (1, true)]
    for (index, cell) in cells.enumerated() {
        // Between the Crenel label (ends at appCenter + 85) and the Applications icon
        // (starts at applicationsCenter − 56), with equal room above and below.
        let rect = CGRect(x: appCenter.x - 5, y: appCenter.y + 98 + CGFloat(index) * 16, width: 10, height: 10)
        let path = CGPath(roundedRect: rect, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        if cell.lit {
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 10, color: teal.withAlphaComponent(0.9).cgColor)
            cg.addPath(path)
            cg.setFillColor(teal.cgColor)
            cg.fillPath()
            cg.restoreGState()
            let core = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [tealCore.cgColor, teal.cgColor] as CFArray, locations: [0, 1])!
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            cg.drawRadialGradient(core, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                                  endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: 6, options: [])
            cg.restoreGState()
        } else {
            cg.addPath(path)
            cg.setFillColor(ink1.withAlphaComponent(cell.alpha).cgColor)
            cg.fillPath()
        }
    }

    // A teal pool of light where Applications sits.
    let pool = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [teal.withAlphaComponent(0.22).cgColor, teal.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    cg.saveGState()
    cg.translateBy(x: applicationsCenter.x, y: applicationsCenter.y + 10)
    cg.scaleBy(x: 1.9, y: 0.75)
    cg.drawRadialGradient(pool, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 70, options: [])
    cg.restoreGState()

    // Finder draws icon labels in black whatever the background, so each label gets a
    // light plate to sit on. Centres measured in Finder on macOS 26/27 at icon size 112.
    for (label, centerY) in [("Crenel", appCenter.y + 74), ("Applications", applicationsCenter.y + 74)] {
        let width = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13)]).size().width + 22
        let plate = CGRect(x: size.width / 2 - width / 2, y: centerY - 11, width: width, height: 22)
        cg.addPath(CGPath(roundedRect: plate, cornerWidth: 11, cornerHeight: 11, transform: nil))
        cg.setFillColor(ink1.withAlphaComponent(0.92).cgColor)
        cg.fillPath()
    }

    // Footer: version, quiet.
    let footer = NSAttributedString(string: "Crenel \(version) · open source", attributes: [
        .font: NSFont(name: "Geist-Regular", size: 10) ?? NSFont.systemFont(ofSize: 10),
        .foregroundColor: NSColor(srgbRed: 0x4C / 255, green: 0x4A / 255, blue: 0x47 / 255, alpha: 1)
    ])
    cg.saveGState()
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    let footerSize = footer.size()
    // Flipped back, so y counts from the bottom of the tall image: the footer sits 16 pt
    // above the bottom of the 520 pt layout.
    footer.draw(at: CGPoint(x: (size.width - footerSize.width) / 2, y: size.height - layoutHeight + 14))
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let data = render(scale: scale).representation(using: .png, properties: [:])!
    try data.write(to: outputDir.appending(path: name))
}
print("wrote \(outputDir.path)/background.png and background@2x.png")
