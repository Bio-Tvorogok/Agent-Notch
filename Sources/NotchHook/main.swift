import Foundation
import NotchCore

// notch-hook <claude|codex>: Claude Code or Codex runs this for every hook event, with the event JSON on stdin.
// It hands the event to Agents Notch. For a permission request it waits for a click in the notch and prints the
// decision; when the app is not running or nobody clicks, it prints nothing and the agent asks as usual.
// It always exits 0: a broken notch must never break an agent.

let args = CommandLine.arguments
guard args.count > 1, let vendor = Vendor(rawValue: args[1]) else { exit(0) }
let input = FileHandle.standardInput.readDataToEndOfFile()
guard input.count < HookServer.maxLine - 4096,
      let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      let event = payload["hook_event_name"] as? String else { exit(0) }
let parsed = HookEvent(vendor: vendor, payload: payload)
// PreToolUse holds the call only for the entry installed with --wait and only for a question or plan; the async one reports and leaves.
let holds = event == "PermissionRequest" || (args.contains("--wait") && parsed?.waitsForAnswer == true)
let wait = holds ? Double(HookInstaller.wait) : 0
if let decision = HookClient.send(vendor: vendor, payload: input, wait: wait),
   let out = HookReply.helperStdout(event: parsed, name: event, decision: decision) {
    FileHandle.standardOutput.write(Data((out + "\n").utf8))
}
exit(0)
