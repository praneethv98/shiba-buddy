import AppKit

// Deterministic checks for the pup: pointer chasing, climbing, hops, bounds, Dock naps and sprites.
func runSelfTests() {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    func puppy() -> Pup {
        let p = Pup(); p.x = 400; p.ground = 0; p.span = 0...1000
        p.mmToPt = 2; p.start(.sit, 1000)
        return p
    }
    for fps in [30.0, 60.0] {
        let p = puppy()
        let dt = 1 / fps
        for _ in 0..<Int(fps * 4) { p.update(dt, mouse: P(520, 30), render: false) }
        check(p.act == .chase, "Pointer should trigger chase")
        check(abs(p.x - 520) < 12, "Pup should approach the pointer")
        let settled = p.x
        let facing = p.facing
        for _ in 0..<Int(fps * 4) { p.update(dt, mouse: P(520, 30), render: false) }
        check(abs(p.x - settled) < 1, "Stationary pointer must not make the pup pace")
        check(p.facing == facing && p.pose == .sit, "Pup should rest without flipping")
        for i in 0..<Int(fps * 3) {
            p.update(dt, mouse: P(520 + sin(Double(i)) * 3, 30), render: false)
        }
        check(abs(p.x - settled) < 1, "Tiny pointer movements must stay inside the settling zone")
        for _ in 0..<Int(fps * 0.3) { p.update(dt, mouse: P(1000, 600), render: false) }
        check(p.act == .chase, "Brief pointer exits must not toggle chase")
        for _ in 0..<Int(fps * 0.3) { p.update(dt, mouse: P(1000, 600), render: false) }
        check(p.act == .sit, "Sustained pointer exit should return to rest")
    }
    let p = puppy()
    p.lift = 70; p.start(.sleep, 1000)
    p.actT = 5
    for _ in 0..<55 { p.update(1 / 60, mouse: P(450, 90), render: false) }
    check(p.climb != nil && p.pose == .hopUp, "Climbing pose must survive chase logic")
    check(p.x == 400, "Pup should finish climbing down before chasing")
    for _ in 0..<60 { p.update(1 / 60, mouse: P(450, 30), render: false) }
    check(p.climb == nil && p.lift == 0, "Pup should land on the floor")

    let jumper = puppy()
    var jumps = 0, wasAirborne = false
    for _ in 0..<600 {
        jumper.update(1 / 60, mouse: P(400, 100), render: false)
        let airborne = jumper.hop > 0
        if airborne && !wasAirborne { jumps += 1 }
        wasAirborne = airborne
        check(jumper.hop >= 0 && jumper.x >= 0 && jumper.x <= 1000, "Physics must remain bounded")
    }
    check(jumps >= 2 && jumps <= 4, "Hover jumps must have a cooldown")

    let edge = puppy(); edge.x = 990; edge.mmToPt = 5
    for _ in 0..<180 { edge.update(1 / 60, mouse: P(1100, 30), render: false) }
    check(edge.x <= 1000 && edge.x >= 988, "Chase should stay inside the walking span")

    let nap = puppy()
    let apps = [DockIcon(id: "app-a", frame: CGRect(x: 360, y: 10, width: 50, height: 50)),
                DockIcon(id: "app-b", frame: CGRect(x: 450, y: 10, width: 60, height: 80))]
    nap.refreshIcons(apps); nap.iconTop = 90
    nap.seekSleep()
    check(nap.act == .sleepGo && apps.contains { $0.frame.midX == nap.targetX }, "Nap should head for a Dock icon")
    let spot = nap.targetX
    for _ in 0..<900 { nap.update(1 / 60, mouse: P(-1000, -1000), render: false) }
    check(nap.act == .sleep && nap.climb == nil, "Pup should reach its icon and fall asleep")
    check(abs(nap.x - spot) < 2.5, "Sleeping pup should be on the chosen icon")
    check(abs(nap.lift - (nap.iconTop - nap.ground - 8)) < 0.1, "Pup should hop up onto the icon row")

    // Without Accessibility there are no icon frames: it must still nap on the Dock.
    let blind = puppy(); blind.iconTop = 60
    blind.refreshIcons([]); blind.seekSleep()
    check(blind.act == .sleepGo && blind.span.contains(blind.targetX), "Nap without icons should pick a spot on the Dock")
    for _ in 0..<1800 { blind.update(1 / 60, mouse: P(-1000, -1000), render: false) }
    check(blind.act == .sleep, "Pup should still sleep when icon positions are unavailable")


    for pose in [PupPose.sit, .walk, .run, .sniff, .dig, .kick, .hopUp, .sleep] {
        let p = puppy(); p.pose = pose
        let frame = p.renderFrame()
        check(frame.img.width == PCW && frame.img.height == PCH, "Each pose must render")
    }
    // Verify every sprite input row fits its allocated pixel buffer.
    for rows in PUP_ART.values {
        check(!rows.isEmpty && rows.allSatisfy { $0.count <= rows[0].count }, "Pup art row exceeds allocated width")
    }
    print("Passed \(checks) checks: cursor settling, climbing, hop cooldown, bounds, Dock naps (with and without icon positions) and sprite rendering.")
}
