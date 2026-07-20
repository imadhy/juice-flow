// Génère Resources/AppIcon.icns sans Xcode ni outil de design :
//   swift scripts/make-icon.swift
// Dessine le master 1024 px (squircle dégradé + éclair), décline les tailles
// avec sips, assemble avec iconutil.
import AppKit

let canvas: CGFloat = 1024
let masterURL = URL(fileURLWithPath: "build/icon/icon_1024.png")
try FileManager.default.createDirectory(at: masterURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let copy = image.copy() as! NSImage
    copy.lockFocus()
    color.set()
    NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
    copy.unlockFocus()
    return copy
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Squircle aux proportions des icônes macOS (~80 % du canevas).
let inset: CGFloat = 100
let squircle = NSBezierPath(
    roundedRect: NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset),
    xRadius: 185, yRadius: 185
)
NSGradient(colors: [
    NSColor(calibratedRed: 0.02, green: 0.23, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.42, alpha: 1),
])!.draw(in: squircle, angle: 90)

// Éclair blanc, léger relief.
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .bold)
if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let white = tinted(bolt, .white)
    let scale = 520 / max(white.size.width, white.size.height)
    let size = NSSize(width: white.size.width * scale, height: white.size.height * scale)
    let origin = NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()

    white.draw(in: NSRect(origin: origin, size: size))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("échec du rendu PNG")
}
try png.write(to: masterURL)
print("✅ master : \(masterURL.path)")
