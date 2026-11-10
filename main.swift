import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--iconset"), i + 1 < args.count { writeIconset(args[i + 1]); exit(0) }
if args.contains("--self-test") { runSelfTests(); exit(0) }
if let i = args.firstIndex(of: "--pupsheet"), i + 1 < args.count { PupController.sheet(args[i + 1]); exit(0) }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
