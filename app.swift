import AppKit
import QuartzCore

// Menu bar app that owns the pup window and its frame timer.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var timer: Timer?
    var timerInterval = 0.0
    var last = CACurrentMediaTime()
    var paused = false, sleeping = false
    var pup: PupController?
    let d = UserDefaults.standard

    func applicationDidFinishLaunching(_ n: Notification) {
        if !d.bool(forKey: "hidePup") { pup = PupController() }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = statusIcon()
        status.button?.toolTip = "Shiba Buddy"
        let menu = NSMenu(); menu.delegate = self; status.menu = menu
        if !d.bool(forKey: "firstRunDone") {
            d.set(true, forKey: "firstRunDone")
            if !Login.enabled { Login.set(true) }   // start at login by default
        }
        refreshTimer()
    }

    @objc func screensChanged() { pup?.layout() }
    @objc func willSleep() { sleeping = true; timer?.invalidate(); timer = nil; timerInterval = 0 }
    @objc func didWake() { sleeping = false; last = CACurrentMediaTime(); pup?.layout(); refreshTimer() }

    // 30 FPS while awake, 15 while napping, 2 when hidden or paused.
    func refreshTimer() {
        guard !sleeping else { return }
        let active = pup != nil && !paused
        let fps: Double = active ? (pup?.pup.act == .sleep ? 15 : 30) : 2
        let interval = 1 / fps
        guard abs(interval - timerInterval) > 0.0001 || timer == nil else { return }
        timer?.invalidate(); timerInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.frame() }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    func frame() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.1); last = now
        if !paused { pup?.tick(dt) }
        refreshTimer()
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let show = item("Show puppy", #selector(togglePup)); show.state = pup != nil ? .on : .off; m.addItem(show)
        let pause = item(paused ? "Resume puppy" : "Pause puppy", #selector(togglePause), key: "p"); pause.isEnabled = pup != nil; m.addItem(pause)
        m.addItem(item("Nap on a random app icon", #selector(nap), key: "n"))
        let trusted = AXIsProcessTrusted()
        let ax = item(trusted ? "Dock icon access: allowed" : "Allow naps on Dock icons…", #selector(askAX)); ax.state = trusted ? .on : .off; m.addItem(ax)
        m.addItem(.separator())
        let login = item("Open at login", #selector(toggleLogin)); login.state = Login.enabled ? .on : .off; m.addItem(login)
        m.addItem(item("Quit Shiba Buddy", #selector(quit), key: "q"))
    }
    func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key); it.target = self; return it
    }

    @objc func togglePup() {
        if let p = pup { p.close(); pup = nil; d.set(true, forKey: "hidePup") }
        else { pup = PupController(); paused = false; d.set(false, forKey: "hidePup") }
        refreshTimer()
    }
    @objc func togglePause() { paused.toggle(); last = CACurrentMediaTime(); refreshTimer() }
    @objc func nap() {
        if pup == nil { pup = PupController(); d.set(false, forKey: "hidePup") }
        paused = false
        pup?.layout(); pup?.pup.seekSleep()
        if !AXIsProcessTrusted() { askAX() }
        refreshTimer()
    }
    @objc func askAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts); pup?.layout()
    }
    @objc func toggleLogin() { Login.set(!Login.enabled) }
    @objc func quit() { NSApp.terminate(nil) }

    /// Menu bar icon: the pup's head, drawn small.
    func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18))
        img.lockFocus()
        if let head = PUPI["head"], let c = NSGraphicsContext.current?.cgContext {
            c.interpolationQuality = .none
            c.draw(head, in: CGRect(x: 0, y: 0, width: 18, height: 18))
        }
        img.unlockFocus()
        return img
    }
}
