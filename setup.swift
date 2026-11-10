import AppKit
import ServiceManagement

enum Login {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { NSLog("Shiba Buddy: open at login failed: \(error)") }
    }
}
