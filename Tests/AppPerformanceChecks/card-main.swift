import Foundation
import Combine
import NotchCore

@main struct CardPerformanceChecks {
    @MainActor static func main() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("notch-card-check-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: path) }
        func record(_ text: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]]) + Data([10])
        }
        try record("ready").write(to: path)
        let model = CardDetailModel()
        var details = 0
        var loadingUpdates = 0
        let detailSub = model.$detail.sink { if $0 != nil { details += 1 } }
        let loadingSub = model.$loading.sink { _ in loadingUpdates += 1 }
        let agent = Agent(id: "probe", vendor: .codex, title: "probe", state: .working, project: "probe", logPath: path.path)
        model.show(agent)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard details == 1, model.detail?.lastMessage == "ready", !model.loading else {
            print("FAIL initial card data did not load"); exit(1)
        }
        let loadedUpdates = loadingUpdates
        RunLoop.main.run(until: Date().addingTimeInterval(3.2))
        guard details == 1, loadingUpdates == loadedUpdates else {
            print("FAIL unchanged card republished: detail=\(details), loading=\(loadingUpdates - loadedUpdates)"); exit(1)
        }
        let file = try FileHandle(forWritingTo: path)
        try file.seekToEnd(); try file.write(contentsOf: record("updated")); try file.close()
        RunLoop.main.run(until: Date().addingTimeInterval(3.2))
        guard details == 2, model.detail?.lastMessage == "updated" else {
            print("FAIL changed card data did not refresh"); exit(1)
        }
        model.close()
        model.show(agent)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard model.detail?.lastMessage == "updated", !model.loading else {
            print("FAIL reopening did not load current data"); exit(1)
        }
        model.close()
        withExtendedLifetime((detailSub, loadingSub)) {}
        print("OK card publication, live refresh and reopening checks")
    }
}
