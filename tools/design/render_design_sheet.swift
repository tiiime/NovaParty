// Render the SVG design boards with macOS AppKit. Run from the repository root.
import AppKit
import CoreText
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let font = root.appendingPathComponent("assets/fonts/NotoSansSC.ttf")
CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
let output = root.appendingPathComponent("build/design")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for filename in CommandLine.arguments.dropFirst() {
    guard let picture = NSImage(contentsOfFile: filename) else { fatalError("Cannot load \(filename)") }
    let size = picture.size
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot allocate preview") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    picture.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let destination = output.appendingPathComponent(URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + ".png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
    print(destination.path)
}
