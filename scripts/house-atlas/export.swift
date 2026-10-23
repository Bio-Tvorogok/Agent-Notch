import AppKit
import WebKit

// Loads room/index.html in a WKWebView sized like the main screen (the same engine and size as the wallpaper),
// runs export.js in it and writes the atlas pages, house.json and the page's own reference frame.
// usage: export <room/index.html> <export.js> <out dir> <hour> [parts <check dir>]
// With "parts" (scripts/house-atlas/parts.js) the script streams its files to Swift with
// webkit.messageHandlers.out.postMessage({ path, data: dataURL | text }) and returns only a short summary line;
// a path starting with "check/" goes to the check dir. Without it the script returns the phase-0 JSON object.
let args = CommandLine.arguments
guard args.count >= 5, let hour = Double(args[4]) else {
    FileHandle.standardError.write("usage: export <index.html> <export.js> <out dir> <hour>\n".data(using: .utf8)!); exit(2)
}
let page = URL(fileURLWithPath: args[1]).standardizedFileURL.absoluteURL, script = try String(contentsOfFile: args[2], encoding: .utf8)
let out = URL(fileURLWithPath: args[3], isDirectory: true).absoluteURL
let partsMode = args.count >= 6 && args[5] == "parts"
let refOnly = ProcessInfo.processInfo.environment["HOUSE_REF_ONLY"] == "1"
let checkDir = URL(fileURLWithPath: args.count >= 7 ? args[6] : ".build/parts-check", isDirectory: true).absoluteURL
let timeout = Double(ProcessInfo.processInfo.environment["HOUSE_TIMEOUT"] ?? "") ?? (partsMode ? 900 : 60)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let screen = partsMode ? nil : NSScreen.screens.first
if !partsMode && screen == nil { fputs("no screen\n", stderr); exit(1) }
let exportFrame = partsMode ? NSRect(x: 0, y: 0, width: 1728, height: 1117) : screen!.frame
// the insets the app sends the page (RoomWallpaper.syncInsets)
let top = partsMode ? 32.0 : screen!.frame.maxY - screen!.visibleFrame.maxY, bottom = partsMode ? 70.0 : screen!.visibleFrame.minY - screen!.frame.minY
let icons = partsMode ? true : (UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool ?? true)
let insets: [String: Double] = ["top": top, "bottom": bottom, "right": partsMode ? 120 : (icons ? 120 : 0)]

let w = NSWindow(contentRect: exportFrame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1) // under the desktop picture: never seen
let conf = WKWebViewConfiguration()
if partsMode { conf.websiteDataStore = .nonPersistent() }
final class Sink: NSObject, WKScriptMessageHandler {
    var written = 0
    var received = Set<String>()
    var expected: Set<String>?
    var summary = ""
    func finishIfReady() {
        guard let expected, expected.isSubset(of: received) else { return }
        if refOnly { // a check-only script (harness/ref.js): every promised file arrived, no atlas to validate
            guard received == expected else { fputs("unexpected output files\n", stderr); exit(1) }
            print(summary); print("wrote \(written) files; pinned viewport 1728x1117, DPR 2, autumn")
            exit(0)
        }
        guard received == expected,
              let data = try? Data(contentsOf: out.appendingPathComponent("parts.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = manifest["pages"] as? [[String: Any]] else {
            fputs("invalid parts delivery or manifest\n", stderr); exit(1)
        }
        let names = Set(["parts.json"] + pages.flatMap { [$0["file"] as! String, $0["fileE"] as! String] })
        let actual = Set(((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).filter {
            $0 == "parts.json" || ($0.hasPrefix("parts-") && $0.hasSuffix(".png"))
        })
        guard actual == names, Set(expected.filter { !$0.hasPrefix("check/") }) == names else {
            fputs("parts output file set mismatch\n", stderr); exit(1)
        }
        print(summary)
        print("wrote \(written) files; pinned viewport 1728x1117, DPR 2, autumn")
        exit(0)
    }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: String], let path = d["path"], let body = d["data"] else { return }
        let isCheck = path.hasPrefix("check/")
        let url = (isCheck ? checkDir.appendingPathComponent(String(path.dropFirst(6))) : out.appendingPathComponent(path))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if body.hasPrefix("data:") {
                guard let comma = body.firstIndex(of: ","),
                      let bytes = Data(base64Encoded: String(body[body.index(after: comma)...])), !bytes.isEmpty else {
                    fputs("invalid image data for \(path)\n", stderr); exit(1)
                }
                try bytes.write(to: url)
            } else { try Data(body.utf8).write(to: url) }
        } catch { fputs("write failed for \(path): \(error)\n", stderr); exit(1) }
        guard received.insert(path).inserted else { fputs("duplicate output: \(path)\n", stderr); exit(1) }
        written += 1
        finishIfReady()
    }
}
let sink = Sink()
if partsMode { // pages of an earlier export with more of them must not linger
    for f in (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? [] where f == "parts.json" || (f.hasPrefix("parts-") && f.hasSuffix(".png")) { try FileManager.default.removeItem(at: out.appendingPathComponent(f)) }
}
conf.userContentController.add(sink, name: "out")
let web = WKWebView(frame: NSRect(origin: .zero, size: exportFrame.size), configuration: conf)
w.contentView = web
w.orderFrontRegardless()

final class Loader: NSObject, WKNavigationDelegate {
    var done: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?() }
}
let loader = Loader()
web.navigationDelegate = loader
var u = URLComponents(url: page, resolvingAgainstBaseURL: false)!
u.queryItems = [URLQueryItem(name: "nodemo", value: "1"), URLQueryItem(name: "hour", value: String(hour)), URLQueryItem(name: "weather", value: "clear")]
if partsMode { u.queryItems!.append(URLQueryItem(name: "season", value: "autumn")) }
if let scene = ProcessInfo.processInfo.environment["HOUSE_SCENE"] { u.queryItems!.append(URLQueryItem(name: "scene", value: scene)) } // "extra": the page's extra-screen scene (harness/extra-ref.js)
web.loadFileURL(u.url!, allowingReadAccessTo: page.deletingLastPathComponent())

func data(fromURL s: String) -> Data? {
    guard let comma = s.firstIndex(of: ",") else { return nil }
    return Data(base64Encoded: String(s[s.index(after: comma)...]))
}

loader.done = {
    let opt: [String: Any] = ["insets": insets, "project": "Agent-Notch",
                              "agents": [["id": "a1", "vendor": "claude"], ["id": "a2", "vendor": "codex"]]]
    let optJSON = String(data: try! JSONSerialization.data(withJSONObject: opt), encoding: .utf8)!
    // a moment for the page's first layout, then the export
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        web.evaluateJavaScript("window.__HOUSE_EXPORT = \(optJSON);\n" + script) { result, error in
            if let error { fputs("export failed: \(error)\n", stderr); exit(1) }
            if partsMode {
                guard let text = result as? String,
                      let response = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                      let files = response["files"] as? [String], !files.isEmpty,
                      Set(files).count == files.count,
                      let summary = response["summary"] as? String else {
                    fputs("parts returned no delivery manifest\n", stderr); exit(1)
                }
                sink.expected = Set(files)
                sink.summary = summary
                sink.finishIfReady() // otherwise the final posted file completes it; the overall timeout is the deadline
                return
            }
            guard let text = result as? String, var json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let pages = json["pages"] as? [[String: Any]], let reference = json["reference"] as? String
            else { fputs("export returned no data\n", stderr); exit(1) }
            // pages from an earlier export with more of them must not linger (build.sh bundles house-*.png)
            for f in (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? [] where f.hasPrefix("house-") && f.hasSuffix(".png") {
                try? FileManager.default.removeItem(at: out.appendingPathComponent(f))
            }
            var names: [String] = []
            for (i, p) in pages.enumerated() {
                let name = "house-\(i).png"
                try! data(fromURL: p["url"] as! String)!.write(to: out.appendingPathComponent(name))
                names.append(name)
            }
            try! data(fromURL: reference)!.write(to: out.appendingPathComponent("reference.png"))
            json["pages"] = names
            json["reference"] = "reference.png"
            json["screen"] = ["w": screen!.frame.width, "h": screen!.frame.height, "scale": (screen?.backingScaleFactor ?? 1)]
            let body = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            try! body.write(to: out.appendingPathComponent("house.json"))
            let layers = (json["layers"] as? [Any])?.count ?? 0, sprites = (json["sprites"] as? [String: Any])?.count ?? 0
            print("exported \(sprites) sprites in \(names.count) pages, \(layers) layers, canvas \(json["canvas"] ?? "?"), pxd \(json["pxd"] ?? "?") dpr \(json["dpr"] ?? "?")")
            exit(0)
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { fputs("export timed out\n", stderr); exit(1) }
app.run()
