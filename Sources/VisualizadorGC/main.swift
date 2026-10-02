import AppKit

if CommandLine.arguments.contains("--selftest") { Markdown.selfTest(); print("ok"); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.regular)
_ = NSDocumentController.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
