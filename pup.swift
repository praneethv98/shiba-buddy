// Shiba pup that lives on the Dock: walks, sniffs, sits and wags, sleeps on a Dock icon
// (breathing, rolling over, kicking, snot bubble), finds and buries bones, and chases the
// mouse pointer when it comes within ~10 cm.

import AppKit
import ApplicationServices

// MARK: - Art

func pixelImage(_ rows: [String], _ pal: [Character: (Int, Int, Int)]) -> CGImage {
    let h = rows.count, w = rows[0].count
    var px = [UInt8](repeating: 0, count: w * h * 4)
    for (y, row) in rows.enumerated() {
        for (x, ch) in row.enumerated() {
            guard let c = pal[ch] else { continue }
            let i = (y * w + x) * 4
            px[i] = UInt8(c.0); px[i + 1] = UInt8(c.1); px[i + 2] = UInt8(c.2); px[i + 3] = 255
        }
    }
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}
let PUPI: [String: CGImage] = PUP_ART.mapValues { pixelImage($0, PUP_PAL) }
func pk(_ k: Character, _ a: CGFloat = 1) -> CGColor {
    let v = PUP_PAL[k] ?? (255, 0, 255)
    return CGColor(srgbRed: CGFloat(v.0) / 255, green: CGFloat(v.1) / 255, blue: CGFloat(v.2) / 255, alpha: a)
}
let FUR = pk("e"), FUR_RIM = pk("l"), FUR_FAR = pk("c"), CREAM = pk("w"), PUP_OUT = pk("a")
let DIRT = [RGB(139, 94, 60), RGB(110, 72, 44), RGB(170, 122, 80)]

// pose canvas (art px == points)
let PCW = 100, PCH = 76
let PC0: CGFloat = 50, PY0: CGFloat = 4   // anchor: center-bottom (feet)

enum PupPose { case sit, look, walk, run, sniff, dig, kick, sleep, hopUp }

struct PupFrame { let img: CGImage; let nose: CGPoint; let mouth: CGPoint; let headTop: CGPoint }

// MARK: - Pup

struct DockIcon: Equatable {
    let id: String
    let frame: CGRect
}

final class Pup {
    // placement
    var x: CGFloat = 0
    var ground: CGFloat = 0           // world y of the walking line (bottom of the Dock)
    var span: ClosedRange<CGFloat> = 0...100
    var icons: [DockIcon] = []          // Dock icon frames (AppKit coords) when Accessibility allows
    var sleepIconID: String?
    var iconTop: CGFloat = 0          // top of the Dock icons (estimated without Accessibility)
    var previousSleepIconID: String?
    var wakeHoverTime = 0.0
    var mmToPt: CGFloat = 4.4

    // body state
    var lift: CGFloat = 0             // height above ground (sitting on an icon)
    var climb: (from: CGFloat, to: CGFloat, t: Double)?
    var hop: CGFloat = 0, hopV: CGFloat = 0
    var facing: CGFloat = 1
    var pose: PupPose = .sit
    var clock = 0.0
    var legPh: CGFloat = 0
    var tailA: CGFloat = 0
    var wag: Double = 0               // wag speed (rad/s)

    // brain
    enum Act { case walk, sniff, sit, sleepGo, sleep, boneSeek, boneCarry, boneDig, boneBury, boneFill, boneLook, chase }
    var act: Act = .sit
    var actT = 0.0, actDur = 2.0
    var targetX: CGFloat = 0
    var excite = 0.0                  // "!" pop when it spots the pointer

    // sleep
    var sleepVar = 0, sleepVarT = 0.0, nextSleepMove = 8.0
    var rollT = -1.0                  // roll-over animation
    var bubble: CGFloat = 0
    var zs: [(p: CGPoint, life: Double)] = []
    var zT = 0.0

    // bone
    var boneX: CGFloat?, boneHeld = false, boneSink: CGFloat = 0, boneFrom: CGFloat = 0
    var holeX: CGFloat?, holeDepth: CGFloat = 0, holeFill: CGFloat = 0, moundLife = 0.0
    var dirt: [(p: CGPoint, v: CGPoint, c: RGB, life: Double)] = []
    var pops: [(p: CGPoint, life: Double)] = []

    var lastFrame: PupFrame?
    var chaseVelocity: CGFloat = 0
    var chaseTarget: CGFloat = 0
    var chaseMoving = false
    var pointerNearTime = 0.0, pointerFarTime = 0.0
    var jumpCooldown = 0.0, hoverTime = 0.0
    var landing = 0.0
    var gait: CGFloat = 0
    var renderedPose: PupPose = .sit
    var poseBlend = 1.0
    var previousFrame: PupFrame?


    var bodyY: CGFloat { ground + lift + hop }
    var center: CGPoint { P(x, bodyY + 18) }
    var range: CGFloat { 100 * mmToPt }   // 10 cm

    func start(_ a: Act, _ d: Double) { act = a; actT = 0; actDur = d }

    func pick() {
        wag = 0
        switch Int.random(in: 0..<100) {
        case 0..<28: start(.walk, Double(rnd(3, 7))); targetX = rnd(span.lowerBound, span.upperBound)
        case 28..<40: start(.sniff, Double(rnd(2, 4)))
        case 40..<58: start(.sit, Double(rnd(4, 8))); wag = 14
        case 58..<78:
            seekSleep()
        default:
            if holeX == nil { start(.boneSeek, 30); boneX = nil } else { start(.sit, 4); wag = 14 }
        }
    }

    /// Original nap behavior: walk to a random Dock icon (or a random spot on the Dock
    /// when icon positions aren't available), hop up and sleep there.
    func seekSleep() {
        sleepIconID = nil
        targetX = icons.isEmpty ? rnd(span.lowerBound, span.upperBound) : icons.randomElement()!.frame.midX
        chaseVelocity = 0; chaseMoving = false; hop = 0; hopV = 0; wag = 0
        boneHeld = false; boneX = nil
        if lift > 0 { climbTo(0) }
        start(.sleepGo, 30)
    }

    func refreshIcons(_ updated: [DockIcon]) { icons = updated }

    @discardableResult
    func move(to tx: CGFloat, _ speed: CGFloat, _ dt: Double) -> Bool {
        let dx = tx - x
        if abs(dx) < 2 { return true }
        facing = dx > 0 ? 1 : -1
        let step = min(abs(dx), speed * CGFloat(dt))
        x += facing * step
        legPh += step * 0.22
        return false
    }

    func clampX(_ v: CGFloat) -> CGFloat { min(max(v, span.lowerBound), span.upperBound) }

    func climbTo(_ h: CGFloat) { climb = (lift, h, 0) }

    func kickDirt(from p: CGPoint, dir: CGFloat, n: Int) {
        for _ in 0..<n {
            dirt.append((p + P(rnd(-2, 2), rnd(0, 2)), P(dir * rnd(40, 140), rnd(60, 180)), DIRT.randomElement()!, 1.2))
        }
    }

    // MARK: update

    func update(_ dt: Double, mouse: CGPoint, render: Bool = true) {
        clock += dt; actT += dt
        excite -= dt
        let fdt = CGFloat(dt)

        // Measure proximity from the ground so a hop cannot trigger enter/exit loops.
        let distance = (mouse - P(x, ground + 24)).len
        pointerNearTime = distance < range ? pointerNearTime + dt : 0
        pointerFarTime = distance > range * 1.35 ? pointerFarTime + dt : 0
        jumpCooldown = max(0, jumpCooldown - dt)
        landing = max(0, landing - dt)
        // Walking to a nap has priority. Wake only after a deliberate close hover.
        wakeHoverTime = act == .sleep && (mouse - center).len < 60 ? wakeHoverTime + dt : 0
        let wantsChase = act == .sleep ? (actT > 4 && wakeHoverTime > 0.8) : pointerNearTime > 0.12
        if wantsChase && act != .chase && act != .sleepGo && climb == nil {
            if act == .sleep { pops.append((P(x, bodyY + 30), 0.5)); sleepIconID = nil }
            if boneHeld { boneHeld = false; boneX = nil }
            if lift > 0 { climbTo(0) }
            chaseTarget = clampX(mouse.x)
            chaseVelocity = 0; chaseMoving = false; hoverTime = 0
            start(.chase, .infinity); excite = 0.7
        } else if act == .chase && pointerFarTime > 0.45 && climb == nil && hop == 0 {
            chaseVelocity = 0; chaseMoving = false; hoverTime = 0
            start(.sit, 1.5); wag = 10
        }

        if let c = climb {   // little jump onto / off a Dock icon
            let t = min(c.t + dt / 0.45, 1)
            let eased = t * t * (3 - 2 * t)
            lift = c.from + (c.to - c.from) * CGFloat(eased) + 16 * CGFloat(sin(.pi * t))
            climb = t >= 1 ? nil : (c.from, c.to, t)
            if t >= 1 { lift = c.to }
            pose = .hopUp
        }

        switch act {
        case .walk:
            pose = .walk
            if move(to: targetX, 32, dt) || actT > actDur { pick() }
        case .sniff:
            pose = .sniff
            x = clampX(x + facing * 5 * fdt); legPh += 5 * fdt * 0.22
            if actT > actDur { pick() }
        case .sit:
            pose = .sit
            if actT > actDur { pick() }
        case .sleepGo:
            if climb == nil {
                pose = .walk
                if move(to: targetX, 34, dt) {
                    start(.sleep, Double(rnd(25, 50)))
                    climbTo(max(0, iconTop - ground - 8))
                    bubble = -0.5; sleepVar = 0; nextSleepMove = Double(rnd(5, 10))
                    wakeHoverTime = 0
                } else if actT > actDur { pick() }
            }
        case .sleep:
            if climb == nil { pose = .sleep }
            updateSleep(dt)
            if actT > actDur { climbTo(0); start(.sit, 3); wag = 10 }
        case .boneSeek:
            if boneX == nil { boneX = clampX(x + facing * rnd(90, 170)) }
            if actT < 1.3 { pose = .sniff }
            else {
                pose = .walk
                if move(to: boneX!, 40, dt) {
                    boneHeld = true; boneX = nil
                    targetX = clampX(x + rnd(-90, 90))
                    start(.boneCarry, 8); wag = 16
                }
            }
        case .boneCarry:
            pose = .walk
            if move(to: targetX, 36, dt) || actT > actDur {
                boneHeld = false
                holeX = x + facing * 22
                boneX = x + facing * 36; boneFrom = boneX!; boneSink = 0
                holeDepth = 0; holeFill = 0
                start(.boneDig, 2.8); wag = 0
            }
        case .boneDig:
            pose = .dig
            holeDepth = min(1, CGFloat(actT / 2.4))
            if chance(0.5) { kickDirt(from: P(x + facing * 16, ground), dir: -facing, n: 1) }
            if actT > actDur { start(.boneBury, 1.4) }
        case .boneBury:
            pose = .sniff
            if let h = holeX {
                let s = CGFloat(min(actT / 0.7, 1))
                boneX = boneFrom + (h - boneFrom) * s
                if actT > 0.7 { boneSink = CGFloat(min((actT - 0.7) / 0.5, 1)) }
            }
            if actT > actDur {
                boneX = nil
                facing = -facing            // turn around and kick dirt back with the hind legs
                start(.boneFill, 2.6)
            }
        case .boneFill:
            pose = .kick
            holeFill = min(1, CGFloat(actT / 2.3))
            if chance(0.55) { kickDirt(from: P(x - facing * 16, ground + 2), dir: -facing, n: 1) }
            if actT > actDur { moundLife = 25; start(.boneLook, 3.2) }
        case .boneLook:
            pose = .look
            // furtive glances: nobody saw that, right?
            let flips: [Double] = [0.5, 1.1, 1.6, 2.3]
            for f in flips where actT - dt < f && actT >= f { facing = -facing }
            if actT > actDur { start(.sit, 4); wag = 16 }
        case .chase:
            // A stable target and separate start/stop thresholds prevent cursor jitter.
            chaseTarget += (clampX(mouse.x) - chaseTarget) * (1 - exp(-fdt * 10))
            let dx = chaseTarget - x
            if abs(dx) > 26 { chaseMoving = true }
            if abs(dx) < 10 { chaseMoving = false }
            if climb == nil {
                let wanted: CGFloat = chaseMoving ? max(-230, min(230, dx * 5)) : 0
                chaseVelocity += (wanted - chaseVelocity) * (1 - exp(-fdt * 12))
                if abs(chaseVelocity) < 2 && !chaseMoving { chaseVelocity = 0 }
                let step = chaseVelocity * fdt
                let oldX = x
                x = clampX(x + step)
                legPh += abs(x - oldX) * 0.18
                if abs(chaseVelocity) > 24 && abs(dx) > 18 { facing = chaseVelocity > 0 ? 1 : -1 }
            }
            pose = abs(chaseVelocity) > 15 ? (abs(chaseVelocity) > 100 ? .run : .walk) : .sit
            wag = chaseMoving ? 17 : 10
            let hovering = abs(mouse.x - x) < 35 && mouse.y > ground + 65 && mouse.y < ground + 180
            hoverTime = hovering && !chaseMoving ? hoverTime + dt : 0
            if hoverTime > 0.65 && jumpCooldown == 0 && hop == 0 && lift == 0 && climb == nil {
                hopV = 260; jumpCooldown = 2.8; hoverTime = 0
            }
        }

        // hop physics
        if hop > 0 || hopV > 0 {
            hopV -= 1100 * fdt; hop += hopV * fdt
            if hop <= 0 { hop = 0; hopV = 0; landing = 0.16 }
        }
        if hop > 0 || climb != nil { pose = .hopUp }

        let wantedTail = wag > 0 ? CGFloat(sin(clock * wag)) * 16 : CGFloat(sin(clock * 1.5)) * 3
        tailA += (wantedTail - tailA) * (1 - exp(-fdt * 24))
        let wantedGait: CGFloat = pose == .run ? 1 : pose == .walk ? 0.45 : 0
        gait += (wantedGait - gait) * (1 - exp(-fdt * 12))
        poseBlend = min(1, poseBlend + dt / 0.12)

        // mound fades after a while
        if holeX != nil && act != .boneDig && act != .boneBury && act != .boneFill {
            moundLife -= dt
            if moundLife <= 0 { holeX = nil; holeDepth = 0; holeFill = 0 }
        }
        for i in dirt.indices {
            dirt[i].v.y -= 600 * fdt
            dirt[i].p = dirt[i].p + dirt[i].v * fdt
            dirt[i].life -= dt
            if dirt[i].p.y < ground { dirt[i].p.y = ground; dirt[i].v = .zero }
        }
        dirt.removeAll { $0.life <= 0 }
        for i in pops.indices { pops[i].life -= dt }
        pops.removeAll { $0.life <= 0 }
        for i in zs.indices { zs[i].life -= dt; zs[i].p = zs[i].p + P(6, 12) * fdt }
        zs.removeAll { $0.life <= 0 }

        if render { updateFrame() }
    }

    func updateFrame() {
        if pose != renderedPose {
            previousFrame = lastFrame; renderedPose = pose; poseBlend = 0
        }
        lastFrame = renderFrame()
    }

    func updateSleep(_ dt: Double) {
        guard climb == nil else { return }
        // snot bubble grows and shrinks with breathing, then pops
        bubble += CGFloat(dt / 3.2)
        if bubble > 1 { bubble = -0.6; if let f = lastFrame { pops.append((worldPoint(f.nose), 0.3)) } }
        zT -= dt
        if zT <= 0, let f = lastFrame { zT = 1.7; zs.append((worldPoint(f.headTop) + P(facing * 4, 2), 2.4)) }
        // move in its sleep like people do
        nextSleepMove -= dt
        sleepVarT -= dt
        if sleepVarT <= 0 { sleepVar = 0 }
        if rollT >= 0 { rollT += dt; if rollT > 0.5 { rollT = -1 } }
        if nextSleepMove <= 0 {
            nextSleepMove = Double(rnd(6, 13))
            switch Int.random(in: 0..<4) {
            case 0: rollT = 0; facing = -facing          // roll over
            case 1: sleepVar = 2; sleepVarT = 3.5         // stretch out front paws
            case 2: sleepVar = 3; sleepVarT = 2.2         // dream-running hind leg
            default: sleepVar = 4; sleepVarT = 1.2        // tail flick
            }
        }
    }

    func worldPoint(_ canvas: CGPoint) -> CGPoint { P(x + (canvas.x - PC0) * facing, bodyY + canvas.y - PY0) }

    // MARK: - pose rendering

    var panting: Bool {
        guard !boneHeld && (pose == .run || (pose == .sit && act == .chase && excite > 0)) else { return false }
        // Short, deliberate bursts rather than a permanently open mouth.
        return clock.truncatingRemainder(dividingBy: 3.6) < 0.9
    }

    func renderFrame() -> PupFrame {
        let c = CGContext(data: nil, width: PCW, height: PCH, bitsPerComponent: 8, bytesPerRow: PCW * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setShouldAntialias(false); c.setAllowsAntialiasing(false); c.interpolationQuality = .none
        var nose = P(PC0 + 28, PY0 + 22), mouth = P(PC0 + 22, PY0 + 16), top = P(PC0 + 14, PY0 + 38)
        switch pose {
        case .sit, .look:
            drawTail(c, pivot: P(PC0 - 20, PY0 + 12), angle: tailA)
            c.draw(PUPI[panting ? "sit" : "sitClosed"]!, in: CGRect(x: PC0 - 30, y: PY0, width: 60, height: 50))
            nose = P(PC0 + 28, PY0 + 35); mouth = P(PC0 + 22, PY0 + 29); top = P(PC0 + 12, PY0 + 50)
        case .walk, .run, .sniff, .dig, .kick, .hopUp:
            (nose, mouth, top) = drawStanding(c)
        case .sleep:
            (nose, top) = drawSleeping(c)
        }
        // outline pass: dark edge around light pixels (art already has its own outline)
        let buf = c.data!.assumingMemoryBound(to: UInt8.self)
        let n = PCW * PCH
        var solid = [Bool](repeating: false, count: n), any = [Bool](repeating: false, count: n)
        for i in 0..<n {
            any[i] = buf[i * 4 + 3] > 0
            solid[i] = any[i] && Int(buf[i * 4]) + Int(buf[i * 4 + 1]) + Int(buf[i * 4 + 2]) > 200
        }
        for y in 0..<PCH {
            for x in 0..<PCW {
                let i = y * PCW + x
                if any[i] { continue }
                if (x > 0 && solid[i - 1]) || (x < PCW - 1 && solid[i + 1]) || (y > 0 && solid[i - PCW]) || (y < PCH - 1 && solid[i + PCW]) {
                    buf[i * 4] = 71; buf[i * 4 + 1] = 9; buf[i * 4 + 2] = 10; buf[i * 4 + 3] = 255
                }
            }
        }
        return PupFrame(img: c.makeImage()!, nose: nose, mouth: mouth, headTop: top)
    }

    func drawTail(_ c: CGContext, pivot: CGPoint, angle: CGFloat) {
        c.saveGState()
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: angle * .pi / 180)
        c.draw(PUPI["tail"]!, in: CGRect(x: -10, y: -4, width: 11, height: 14))
        c.restoreGState()
    }

    func leg(_ c: CGContext, _ hx: CGFloat, _ hy: CGFloat, _ ph: CGFloat, _ amp: CGFloat, far: Bool) {
        let sw = sin(ph) * amp
        let up = max(0, cos(ph)) * amp * 0.45
        let foot = P(hx + sw, PY0 + up)
        line(c, P(hx, hy), foot + P(0, 2), 5, far ? FUR_FAR : FUR)
        c.setFillColor(far ? pk("i") : CREAM)
        c.fill(CGRect(x: floor(foot.x - 2.5), y: floor(foot.y), width: 5, height: 2))
    }

    func body(_ c: CGContext, _ r: CGRect, belly: CGFloat = 3) {
        let path = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
        c.addPath(path); c.setFillColor(FUR); c.fillPath()
        c.saveGState(); c.addPath(path); c.clip()
        c.setFillColor(CREAM); c.fill(CGRect(x: r.minX + r.width * 0.45, y: r.minY, width: r.width, height: belly))
        c.setFillColor(FUR_RIM); c.fill(CGRect(x: r.minX + 5, y: r.maxY - 2, width: r.width - 12, height: 1))
        c.setFillColor(pk("b")); c.fill(CGRect(x: r.minX + 8, y: r.maxY - 4, width: 6, height: 1))
        c.restoreGState()
    }

    func drawStanding(_ c: CGContext) -> (CGPoint, CGPoint, CGPoint) {
        var amp: CGFloat = 0, gallop = false, bob: CGFloat = 0
        var headDY: CGFloat = 0, headRot: CGFloat = 0
        var frontAmp: CGFloat? = nil, backAmp: CGFloat? = nil
        var ph = legPh
        switch pose {
        case .walk: amp = 2 + gait * 4.5; bob = (1 - cos(ph * 2)) * 0.4
        case .run: amp = 2 + gait * 4.5; gallop = true; bob = (1 - cos(ph * 2)) * 1.1; headDY = -bob * 0.45; headRot = -3
        case .hopUp: amp = 0; frontAmp = 0; backAmp = 0; headRot = 8
        case .sniff:
            amp = 1.2; headDY = -4; headRot = -18
            headDY -= (sin(clock * 9) + 1) * 0.4
        case .dig:
            ph = CGFloat(clock * 26); frontAmp = 4.5; backAmp = 0
            headDY = -5; headRot = -24
        case .kick:
            ph = CGFloat(clock * 24); frontAmp = 0; backAmp = 7
            headDY = 1; headRot = 6
        default: break
        }
        let fa = frontAmp ?? amp, ba = backAmp ?? amp
        let by = PY0 + bob
        let hipY = by + 13
        let back1 = ph, back2 = ph + .pi
        let front1 = gallop ? ph + 0.6 : ph + .pi, front2 = gallop ? ph + 0.9 : ph
        // far side legs
        leg(c, PC0 - 14, hipY, back2, ba, far: true)
        leg(c, PC0 + 11, hipY, front2, fa, far: true)
        // tail curled over the back
        drawTail(c, pivot: P(PC0 - 19, by + 20), angle: tailA - 6)
        body(c, CGRect(x: PC0 - 23, y: by + 8, width: 39, height: 14))
        // near side legs
        leg(c, PC0 - 18, hipY, back1, ba, far: false)
        leg(c, PC0 + 7, hipY, front1, fa, far: false)
        // head (with chest) — tilted for sniffing / digging
        let head = PUPI[panting ? "head" : "headClosed"]!
        let hx = PC0 + 1, hy = by + 8 + headDY
        let pivot = P(hx + 6, hy + 8)
        c.saveGState()
        c.translateBy(x: pivot.x, y: pivot.y); c.rotate(by: headRot * .pi / 180); c.translateBy(x: -pivot.x, y: -pivot.y)
        c.draw(head, in: CGRect(x: hx, y: hy, width: 29, height: 29))
        c.restoreGState()
        func rot(_ p: CGPoint) -> CGPoint {
            let a = headRot * .pi / 180, d = p - pivot
            return pivot + P(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a))
        }
        let nose = rot(P(hx + 27, hy + 14)), mouth = rot(P(hx + 22, hy + 8)), top = rot(P(hx + 12, hy + 29))
        if boneHeld { drawBone(c, mouth + P(1, -1)) }
        return (nose, mouth, top)
    }

    func drawSleeping(_ c: CGContext) -> (CGPoint, CGPoint) {
        let breath = (sin(clock * 1.7) + 1) / 2
        var squash: CGFloat = 1
        if rollT >= 0 { squash = 0.65 + 0.35 * abs(cos(CGFloat(rollT / 0.5) * .pi)) }
        let h = (12 + breath * 1.5) * squash
        // tail curled along the ground
        let flick: CGFloat = sleepVar == 4 ? CGFloat(sin(clock * 18)) * 20 : 0
        drawTail(c, pivot: P(PC0 - 19, PY0 + 5), angle: 75 + flick)
        // dream-running hind leg
        if sleepVar == 3 {
            let tw = CGFloat(sin(clock * 22)) * 2
            line(c, P(PC0 - 16, PY0 + 5), P(PC0 - 29, PY0 + 3 + tw), 4.5, FUR)
            c.setFillColor(CREAM); c.fill(CGRect(x: PC0 - 32, y: PY0 + 2 + tw, width: 3, height: 3))
        }
        body(c, CGRect(x: PC0 - 23, y: PY0, width: 37, height: h), belly: 2)
        // hind paw tucked
        c.setFillColor(CREAM); c.fill(CGRect(x: PC0 - 14, y: PY0, width: 5, height: 2))
        // front paws (stretch out sometimes)
        let reach: CGFloat = sleepVar == 2 ? 6 + CGFloat(sin(clock * 3)) : 0
        let pr = CGRect(x: PC0 + 8, y: PY0, width: 13 + reach, height: 4)
        c.addPath(CGPath(roundedRect: pr, cornerWidth: 2, cornerHeight: 2, transform: nil)); c.setFillColor(FUR); c.fillPath()
        c.setFillColor(CREAM); c.fill(CGRect(x: pr.maxX - 4, y: pr.minY, width: 4, height: 3))
        // head resting on the paws, rising a pixel with each breath
        let hy = PY0 + 2 + (breath > 0.6 ? 1 : 0)
        let hx = PC0 + 1
        c.draw(PUPI["headSleep"]!, in: CGRect(x: hx, y: hy, width: 29, height: 22))
        return (P(hx + 27, hy + 8), P(hx + 14, hy + 22))
    }

    func drawBone(_ c: CGContext, _ p: CGPoint) {
        let bone = RGB(246, 240, 226), sh = RGB(206, 196, 176)
        c.setFillColor(PUP_OUT); c.fill(CGRect(x: floor(p.x) - 5, y: floor(p.y) - 1, width: 11, height: 4))
        for dx in [CGFloat(-5), 4] {
            disc(c, P(floor(p.x) + dx + 0.5, floor(p.y) + 0.5), 2.2, PUP_OUT)
            c.setFillColor(bone.cg()); c.fill(CGRect(x: floor(p.x) + dx - 1, y: floor(p.y) - 1, width: 2, height: 3))
        }
        c.setFillColor(bone.cg()); c.fill(CGRect(x: floor(p.x) - 4, y: floor(p.y), width: 9, height: 2))
        c.setFillColor(sh.cg()); c.fill(CGRect(x: floor(p.x) - 3, y: floor(p.y), width: 7, height: 1))
    }
}

// MARK: - Dock geometry

enum Dock {
    static func screen(for icons: [CGRect]) -> NSScreen? {
        let screens = NSScreen.screens
        if !icons.isEmpty, let best = screens.max(by: { a, b in
            func area(_ screen: NSScreen) -> CGFloat {
                icons.reduce(0) { total, rect in
                    let intersection = screen.frame.intersection(rect)
                    return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
                }
            }
            return area(a) < area(b)
        }), icons.contains(where: { best.frame.intersects($0) }) { return best }
        return screens.first { $0.visibleFrame.minY > $0.frame.minY + 4 } ?? screens.first
    }

    /// Dock item frames via Accessibility (empty if not permitted).
    static func icons() -> [DockIcon] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        func kids(_ e: AXUIElement) -> [AXUIElement] {
            var v: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v)
            return (v as? [AXUIElement]) ?? []
        }
        let h0 = NSScreen.screens.first?.frame.maxY ?? 0
        var out: [DockIcon] = []
        for list in kids(app) {
            for item in kids(list) {
                var sub: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &sub)
                guard (sub as? String) == "AXApplicationDockItem" else { continue }
                var url: CFTypeRef?, title: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &url)
                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title)
                let id = (url as? URL)?.absoluteString ?? (title as? String)
                guard let id, !id.isEmpty else { continue }
                var pv: CFTypeRef?, sv: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pv)
                AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sv)
                guard let pv, let sv else { continue }
                var p = CGPoint.zero, s = CGSize.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &p)
                AXValueGetValue(sv as! AXValue, .cgSize, &s)
                if s.width > 0 && s.height > 0 {
                    out.append(DockIcon(id: id, frame: CGRect(x: p.x, y: h0 - p.y - s.height, width: s.width, height: s.height)))
                }
            }
        }
        return out
    }

    static func mmToPt(_ s: NSScreen) -> CGFloat {
        guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 4.4 }
        let mm = CGDisplayScreenSize(n.uint32Value)
        return mm.width > 10 ? s.frame.width / mm.width : 4.4
    }
}

// MARK: - Window + controller

final class PupController {
    let pup = Pup()
    var window: NSWindow?
    var screen: NSScreen?
    var ctx: CGContext?
    var bw = 0, bh = 0
    var origin = CGPoint.zero
    var iconRefresh = 0.0

    init() { layout(); pup.x = (pup.span.lowerBound + pup.span.upperBound) / 2; pup.seekSleep() }

    func layout() {
        let allIcons = Dock.icons()
        guard let s = Dock.screen(for: allIcons.map(\.frame)) else { close(); return }
        let changedScreen = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber != s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        screen = s
        let f = s.frame, v = s.visibleFrame
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String ?? "bottom"
        // On a side Dock, keep the pup safely on the desktop floor.
        let icons = orientation == "bottom" ? allIcons.filter { f.intersects($0.frame) && $0.frame.minY >= f.minY - 2 && $0.frame.maxY > f.minY + 8 }.sorted { $0.frame.minX < $1.frame.minX } : []
        pup.ground = f.minY + 3
        pup.refreshIcons(icons)
        pup.iconTop = icons.map(\.frame.maxY).max() ?? max(v.minY - 6, f.minY + 3)
        if let a = icons.map({ $0.frame.midX }).min(), let b = icons.map({ $0.frame.midX }).max() {
            pup.span = a...max(a, b)
        } else {
            pup.span = (v.minX + 40)...max(v.minX + 80, v.maxX - 40)
        }
        pup.x = pup.clampX(changedScreen ? (pup.span.lowerBound + pup.span.upperBound) / 2 : pup.x)
        pup.targetX = pup.clampX(pup.targetX)
        pup.chaseTarget = pup.clampX(pup.chaseTarget)
        pup.mmToPt = Dock.mmToPt(s)
        if changedScreen {
            pup.lift = 0; pup.hop = 0; pup.hopV = 0; pup.climb = nil
            pup.boneX = nil; pup.boneHeld = false; pup.holeX = nil
            pup.dirt = []; pup.zs = []; pup.pops = []
            pup.start(.sit, 2)
        }
        let frame = CGRect(x: pup.x - 96, y: f.minY, width: 192, height: 192)
        if window == nil {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.ignoresMouseEvents = true
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)   // above the Dock
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            view.layer?.magnificationFilter = .nearest
            view.layer?.contentsGravity = .bottomLeft
            view.layer?.contentsScale = 1
            w.contentView = view
            window = w
        }
        window?.orderFrontRegardless()
    }

    func close() { window?.orderOut(nil); window?.close(); window = nil }

    func tick(_ dt: Double) {
        iconRefresh -= dt
        if iconRefresh <= 0 {
            iconRefresh = pup.act == .sleep || pup.act == .sleepGo ? 0.35 : 3
            layout()
        }
        let mouse = NSEvent.mouseLocation
        var remaining = min(dt, 0.1)
        while remaining > 0.000001 {
            let step = min(remaining, 1.0 / 60)
            pup.update(step, mouse: mouse, render: false)
            remaining -= step
        }
        pup.updateFrame()
        render()
    }

    // Keep the backing image near the pup and its props, instead of screen-wide.
    func prepareCanvas() {
        var bounds = CGRect(x: pup.x - 65, y: pup.bodyY - 12, width: 130, height: 110)
        func include(_ p: CGPoint, _ radius: CGFloat) {
            bounds = bounds.union(CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        }
        if let x = pup.holeX { include(P(x, pup.ground), 40) }
        if let x = pup.boneX { include(P(x, pup.ground), 16) }
        for d in pup.dirt { include(d.p, 8) }
        for z in pup.zs { include(z.p, 16) }
        for p in pup.pops { include(p.p, 16) }
        let x = floor(bounds.minX / 64) * 64, y = floor(bounds.minY / 64) * 64
        let width = Int(ceil((bounds.maxX - x) / 64) * 64)
        let height = Int(ceil((bounds.maxY - y) / 64) * 64)
        if width != bw || height != bh || ctx == nil {
            bw = width; bh = height
            ctx = CGContext(data: nil, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: bw * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.setShouldAntialias(false); ctx?.setAllowsAntialiasing(false); ctx?.interpolationQuality = .none
        }
        origin = P(x, y)
        let frame = CGRect(x: x, y: y, width: CGFloat(width), height: CGFloat(height))
        if window?.frame != frame {
            window?.setFrame(frame, display: false)
            window?.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        }
    }

    func render() {
        prepareCanvas()
        guard let c = ctx, let fr = pup.lastFrame else { return }
        let p = pup
        c.clear(CGRect(x: 0, y: 0, width: bw, height: bh))
        func W(_ q: CGPoint) -> CGPoint { P(floor(q.x - origin.x), floor(q.y - origin.y)) }

        // hole / mound
        if let hx = p.holeX {
            let g = W(P(hx, p.ground))
            let open = p.holeDepth * (1 - p.holeFill)
            if open > 0.02 {
                let w = 4 + 14 * open
                c.setFillColor(PUP_OUT); c.fillEllipse(in: CGRect(x: g.x - w / 2 - 1, y: g.y - 2, width: w + 2, height: 6 * open + 3))
                c.setFillColor(RGB(54, 32, 20).cg()); c.fillEllipse(in: CGRect(x: g.x - w / 2, y: g.y - 1, width: w, height: 6 * open + 1))
            }
            let m = max(p.holeFill, open > 0 ? p.holeDepth * 0.5 : 0)
            if m > 0.05 {
                let mw: CGFloat = 16, mh = 2 + 3 * m
                c.setFillColor(PUP_OUT); c.fillEllipse(in: CGRect(x: g.x - mw / 2 - 1 + (open > 0.02 ? -p.facing * 12 : 0), y: g.y - mh, width: mw + 2, height: mh * 2 + 1))
                c.setFillColor(DIRT[0].cg()); c.fillEllipse(in: CGRect(x: g.x - mw / 2 + (open > 0.02 ? -p.facing * 12 : 0), y: g.y - mh + 1, width: mw, height: mh * 2 - 1))
                c.setFillColor(DIRT[2].cg()); c.fill(CGRect(x: g.x - 3 + (open > 0.02 ? -p.facing * 12 : 0), y: g.y + mh - 1, width: 5, height: 1))
            }
        }
        // bone on the ground (sinking into the hole)
        if let bx = p.boneX {
            let g = W(P(bx, p.ground + 2 - p.boneSink * 6))
            c.saveGState()
            if p.boneSink > 0 { c.clip(to: CGRect(x: 0, y: g.y - 6 + p.boneSink * 6 + 1, width: CGFloat(bw), height: CGFloat(bh))) }
            p.drawBone(c, g)
            c.restoreGState()
        }
        // the pup
        let anchor = W(P(p.x, p.bodyY))
        c.saveGState()
        c.translateBy(x: anchor.x, y: anchor.y)
        c.scaleBy(x: p.facing, y: 1)
        let squash = 1 - 0.09 * sin(.pi * CGFloat(p.landing / 0.16))
        c.scaleBy(x: 1 / squash, y: squash)
        let spriteRect = CGRect(x: -PC0, y: -PY0, width: CGFloat(PCW), height: CGFloat(PCH))
        if p.poseBlend < 1, let old = p.previousFrame {
            c.setAlpha(CGFloat(1 - p.poseBlend)); c.draw(old.img, in: spriteRect)
        }
        c.setAlpha(CGFloat(p.poseBlend)); c.draw(fr.img, in: spriteRect)
        c.setAlpha(1)
        c.restoreGState()

        // dirt particles
        for d in p.dirt {
            let q = W(d.p)
            c.setFillColor(d.c.cg(min(1, CGFloat(d.life) * 2))); c.fill(CGRect(x: q.x, y: q.y, width: 2, height: 2))
        }
        // snot bubble
        if p.act == .sleep && p.climb == nil && p.bubble > 0 {
            let breath = (sin(p.clock * 1.7) + 1) / 2
            let r = 1.5 + p.bubble * 5 + breath * 1.5
            let n = W(p.worldPoint(fr.nose)) + P(p.facing * (r - 0.5), -1)
            c.setFillColor(RGB(214, 238, 255).cg(0.45)); c.fillEllipse(in: CGRect(x: n.x - r, y: n.y - r, width: r * 2, height: r * 2))
            c.setStrokeColor(RGB(150, 205, 250).cg(0.95)); c.setLineWidth(1)
            c.strokeEllipse(in: CGRect(x: n.x - r, y: n.y - r, width: r * 2, height: r * 2))
            c.setFillColor(WHITE.cg()); c.fill(CGRect(x: n.x - r * 0.4, y: n.y + r * 0.3, width: 1, height: 1))
        }
        // Zzz
        for z in p.zs {
            let q = W(z.p), a = CGFloat(min(1, z.life))
            let s: CGFloat = 3 + CGFloat(2.4 - z.life) * 1.2
            c.setStrokeColor(RGB(80, 90, 140).cg(a)); c.setLineWidth(1)
            c.move(to: q + P(0, s)); c.addLine(to: q + P(s, s)); c.addLine(to: q); c.addLine(to: q + P(s, 0)); c.strokePath()
        }
        // pops (bubble burst / wake-up)
        for o in p.pops {
            let q = W(o.p), t = CGFloat(1 - o.life / 0.5)
            for k in 0..<6 {
                let a = CGFloat(k) / 6 * .pi * 2
                c.setFillColor(WHITE.cg(1 - t)); c.fill(CGRect(x: q.x + cos(a) * (3 + t * 6), y: q.y + sin(a) * (3 + t * 6), width: 1, height: 1))
            }
        }
        // "!" when it spots the pointer
        if p.excite > 0 {
            let q = W(p.worldPoint(fr.headTop)) + P(0, 6 + CGFloat(1 - p.excite) * 4)
            c.setFillColor(PUP_OUT); c.fill(CGRect(x: q.x - 2, y: q.y - 1, width: 4, height: 11))
            c.setFillColor(RGB(255, 220, 60).cg()); c.fill(CGRect(x: q.x - 1, y: q.y + 3, width: 2, height: 6))
            c.fill(CGRect(x: q.x - 1, y: q.y, width: 2, height: 2))
        }

        CATransaction.begin(); CATransaction.setDisableActions(true)
        window?.contentView?.layer?.contents = c.makeImage()
        CATransaction.commit()
    }

    /// Debug: every pose side by side.
    static func sheet(_ path: String) {
        let poses: [PupPose] = [.sit, .walk, .run, .sniff, .dig, .kick, .hopUp, .sleep]
        let sc = 4
        let W = poses.count * PCW, H = PCH
        let c = CGContext(data: nil, width: W * sc, height: H * sc, bitsPerComponent: 8, bytesPerRow: W * sc * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(RGB(120, 150, 190).cg()); c.fill(CGRect(x: 0, y: 0, width: W * sc, height: H * sc))
        c.interpolationQuality = .none
        for (i, pz) in poses.enumerated() {
            let p = Pup(); p.pose = pz; p.legPh = 1.2; p.clock = 0.3; p.boneHeld = pz == .walk
            let f = p.renderFrame()
            c.draw(f.img, in: CGRect(x: i * PCW * sc, y: 0, width: PCW * sc, height: PCH * sc))
        }
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, c.makeImage()!, nil); CGImageDestinationFinalize(dest)
    }
}
