import AppKit
import WebKit

// Loads room/index.html in a WKWebView sized like the main screen (the same engine and size as the wallpaper),
// runs export.js in it and writes the atlas pages, house.json and the page's own reference frame.
// usage: export <room/index.html> <export.js> <out dir> <hour>
let args = CommandLine.arguments
guard args.count >= 5, let hour = Double(args[4]) else {
    FileHandle.standardError.write("usage: export <index.html> <export.js> <out dir> <hour>\n".data(using: .utf8)!); exit(2)
}
let page = URL(fileURLWithPath: args[1]).standardizedFileURL.absoluteURL, script = try String(contentsOfFile: args[2], encoding: .utf8)
let out = URL(fileURLWithPath: args[3], isDirectory: true).absoluteURL
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
guard let screen = NSScreen.screens.first else { fputs("no screen\n", stderr); exit(1) }
// the insets the app sends the page (RoomWallpaper.syncInsets)
let top = screen.frame.maxY - screen.visibleFrame.maxY, bottom = screen.visibleFrame.minY - screen.frame.minY
let icons = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool ?? true
let insets: [String: Double] = ["top": top, "bottom": bottom, "right": icons ? 120 : 0]

let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1) // under the desktop picture: never seen
let web = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: WKWebViewConfiguration())
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
            json["screen"] = ["w": screen.frame.width, "h": screen.frame.height, "scale": screen.backingScaleFactor]
            let body = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            try! body.write(to: out.appendingPathComponent("house.json"))
            let layers = (json["layers"] as? [Any])?.count ?? 0, sprites = (json["sprites"] as? [String: Any])?.count ?? 0
            print("exported \(sprites) sprites in \(names.count) pages, \(layers) layers, canvas \(json["canvas"] ?? "?"), pxd \(json["pxd"] ?? "?") dpr \(json["dpr"] ?? "?")")
            exit(0)
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { fputs("export timed out\n", stderr); exit(1) }
app.run()
