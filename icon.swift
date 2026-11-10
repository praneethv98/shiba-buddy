import AppKit
import ImageIO

// App icon: the pup's head on a warm tile. ShibaBuddy --iconset <dir.iconset>
func makeIconImage(size: Int) -> CGImage? {
    let art = 64
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let c = CGContext(data: nil, width: art, height: art, bitsPerComponent: 8, bytesPerRow: art * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.setShouldAntialias(false); c.interpolationQuality = .none
    let tile = CGRect(x: 6, y: 6, width: 52, height: 52)
    c.addPath(CGPath(roundedRect: tile, cornerWidth: 12, cornerHeight: 12, transform: nil))
    c.setFillColor(RGB(40, 28, 24).cg()); c.fillPath()
    c.saveGState()
    c.addPath(CGPath(roundedRect: tile.insetBy(dx: 1, dy: 1), cornerWidth: 11, cornerHeight: 11, transform: nil)); c.clip()
    for y in 0..<52 {   // banded sunset gradient
        let t = CGFloat(y / 4 * 4) / 52
        c.setFillColor(RGB(255, 214, 150).mix(RGB(240, 140, 90), t).cg()); c.fill(CGRect(x: 6, y: 6 + y, width: 52, height: 1))
    }
    if let head = PUPI["head"] { c.draw(head, in: CGRect(x: 14, y: 10, width: 36, height: 36)) }
    c.restoreGState()
    guard let small = c.makeImage(),
          let big = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    big.interpolationQuality = size >= art ? .none : .high
    big.draw(small, in: CGRect(x: 0, y: 0, width: size, height: size))
    return big.makeImage()
}

func writeIconset(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            guard let img = makeIconImage(size: px) else { continue }
            let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/\(name)") as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
        }
    }
}
