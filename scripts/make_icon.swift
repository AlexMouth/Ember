// Generates assets/icon-1024.png (macOS squircle + flame). Run: swift scripts/make_icon.swift
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// Apple icon grid: 824pt body centred in 1024 canvas
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); path.fill()
ctx.restoreGState()
ctx.saveGState()
path.addClip()
let bg = NSGradient(colors: [NSColor(red: 0.16, green: 0.09, blue: 0.08, alpha: 1), NSColor(red: 0.07, green: 0.05, blue: 0.06, alpha: 1)])!
bg.draw(in: body, angle: -90)
// warm glow behind the flame
let glow = NSGradient(colors: [NSColor(red: 1, green: 0.45, blue: 0.1, alpha: 0.55), NSColor(red: 1, green: 0.3, blue: 0.1, alpha: 0)])!
glow.draw(fromCenter: NSPoint(x: 512, y: 400), radius: 0, toCenter: NSPoint(x: 512, y: 400), radius: 420, options: [])
// top sheen
let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
sheen.draw(in: NSRect(x: 100, y: 520, width: 824, height: 404), angle: -90)
ctx.restoreGState()
// hairline
NSColor.white.withAlphaComponent(0.12).setStroke(); path.lineWidth = 2; path.stroke()

// flame glyph filled with an orange gradient
let cfg = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
let sym = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
let sz = sym.size
let target = NSRect(x: (S - sz.width) / 2, y: (S - sz.height) / 2 - 10, width: sz.width, height: sz.height)
let mask = NSImage(size: NSSize(width: S, height: S))
mask.lockFocus(); sym.draw(in: target); mask.unlockFocus()
ctx.saveGState()
var rect = CGRect(x: 0, y: 0, width: S, height: S)
if let cg = mask.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
    ctx.clip(to: rect, mask: cg)
    let fl = NSGradient(colors: [NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1), NSColor(red: 1, green: 0.55, blue: 0.12, alpha: 1), NSColor(red: 0.95, green: 0.25, blue: 0.1, alpha: 1)])!
    fl.draw(in: target, angle: -90)
}
ctx.restoreGState()
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/icon-1024.png"))
