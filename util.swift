import AppKit

// Small math, color and drawing helpers used by the pup.

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { P(a.x + b.x, a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { P(a.x - b.x, a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { P(a.x * s, a.y * s) }
    var len: CGFloat { hypot(x, y) }
    var norm: CGPoint { let l = len; return l > 0.0001 ? self * (1 / l) : .zero }
}
func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { a + (b - a) * t }
func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b) }
func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }

struct RGB {
    var r, g, b: CGFloat
    init(_ r: Int, _ g: Int, _ b: Int) { self.r = CGFloat(r) / 255; self.g = CGFloat(g) / 255; self.b = CGFloat(b) / 255 }
    init(f r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }
    func cg(_ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func mul(_ k: CGFloat) -> RGB { RGB(f: r * k, g * k, b * k) }
    func mix(_ o: RGB, _ t: CGFloat) -> RGB { RGB(f: r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t) }
}
let WHITE = RGB(255, 255, 255)

func disc(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: CGColor) {
    c.setFillColor(col); c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}
func line(_ c: CGContext, _ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ col: CGColor) {
    c.setStrokeColor(col); c.setLineWidth(w); c.setLineCap(.round)
    c.move(to: a); c.addLine(to: b); c.strokePath()
}
