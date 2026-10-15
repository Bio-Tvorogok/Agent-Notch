import Foundation
import NotchCore

// notch-hook <claude|codex>: Claude Code or Codex runs this for every hook event, with the event JSON on stdin.
// It hands the event to Agents Notch. For a permission request it waits for a click in the notch and prints the
// decision; when the app is not running or nobody clicks, it prints nothing and the agent asks as usual.
// Hook events always exit 0: a broken notch must never break an agent.
// notch-hook --uninstall-hooks removes our entries from both vendors, like the app flag.
// `brew uninstall --zap` runs it from this copy, because by then the app bundle is already gone.

// A closed stdout pipe must not turn a delivery failure into a hook failure.
signal(SIGPIPE, SIG_IGN)
let args = CommandLine.arguments
if args.count == 2 && args[1] == "--install-hooks" {
    FileHandle.standardError.write(Data("Run the app with --install-hooks to place the helper and pin the app path.\n".utf8))
    exit(1)
}
if args.count == 2 && args[1] == "--uninstall-hooks" {
    // The home is where this copy lives, so the paths match the installed commands exactly; $HOME is the fallback.
    let suffix = "/Library/Application Support/AgentsNotch/notch-hook"
    // realpath, not URL.resolvingSymlinksInPath: that one drops /private and the paths stop matching.
    let me = Bundle.main.executablePath.flatMap { realpath($0, nil) }.map { p in defer { free(p) }; return String(cString: p) } ?? ""
    let home = me.hasSuffix(suffix) ? String(me.dropLast(suffix.count))
        : ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 }
    let inst = home.map { HookInstaller(home: URL(fileURLWithPath: $0)) } ?? HookInstaller()
    exit(inst.editHooks(install: false))
}
guard args.count > 1, let vendor = Vendor(rawValue: args[1]) else { exit(0) }
let input = FileHandle.standardInput.readDataToEndOfFile()
guard input.count < HookServer.maxLine - 4096,
      let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      let event = payload["hook_event_name"] as? String else { exit(0) }
let parsed = HookEvent(vendor: vendor, payload: payload)
// Leave confirmed automatic reviews to Codex without making a decision or showing a human prompt.
if parsed?.isAutomaticReview == true { exit(0) }
// PreToolUse holds the call only for the entry installed with --wait and only for a question or plan; the async one reports and leaves.
let holds = event == "PermissionRequest" || (args.contains("--wait") && parsed?.waitsForAnswer == true)
let wait = holds ? Double(HookInstaller.wait) : 0
_ = HookClient.send(vendor: vendor, payload: input, wait: wait, deliver: { decision in
    guard let out = HookReply.helperStdout(event: parsed, name: event, decision: decision) else { return false }
    return HookClient.writeStdout(out)
})
exit(0)
