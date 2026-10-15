import Foundation
import NotchCore

// A command-line server in an app-shaped path proves helper peer validation without AppKit or real sessions.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let installer = HookInstaller(home: root)
let server = HookServer(path: ConnectionReport.socketPath(installer))
server.onEvent = { _, _ in
    try? Data("unexpected session event".utf8).write(to: root.appendingPathComponent("event-received"))
}
do {
    try server.start()
    try Data().write(to: root.appendingPathComponent("ready"))
    RunLoop.current.run(until: Date().addingTimeInterval(15))
    server.stop()
} catch { exit(1) }
