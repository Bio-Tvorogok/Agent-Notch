import Foundation
import NotchCore
final class ExpirySettings { var appearance = Appearance(); struct Appearance { var finishedMinutes = 1.0 } }
struct ExpiryNames { func name(for path: String?) -> String { "house" } }
final class ExpiryChanges { var count = 0; func send() { count += 1 } }
@main struct ExpiryTimerChecks {
    @MainActor static func main() {
        func expect(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
        let harness = ExpiryHarness()
        var agent = Agent(id: "session", vendor: .claude, title: "build", state: .working, project: "house")
        agent.lastAt = 1
        harness.agents = [agent]
        func receive(_ event: HookEvent, at: Double) {
            var next = harness.hooks
            _ = next.receive(event, ticket: nil, now: at)
            if next != harness.hooks { harness.hookPublication.record(event, ticket: nil, now: at) }
            harness.hooks = next
            harness.rememberHookOutput()
        }
        let stop = HookEvent(vendor: .claude, name: "Stop", sessionId: "session")
        let prompt = HookEvent(vendor: .claude, name: "Notification", sessionId: "session", notificationType: "permission_prompt", message: "Allow?")
        let tool = HookEvent(vendor: .claude, name: "PreToolUse", sessionId: "session")
        receive(stop, at: Date().timeIntervalSince1970 - 59.95)
        expect(harness.hookExpiryTimer != nil, "hook stop arms a timer without starting polling")
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        expect(harness.objectWillChange.count == 1, "timer publishes hook retention expiry without poll")
        expect(harness.hookExpiryTimer == nil, "expired turn leaves no repeating timer")
        receive(prompt, at: Date().timeIntervalSince1970 - 3599.95)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        expect(harness.objectWillChange.count == 2, "timer publishes prompt expiry without poll")
        receive(prompt, at: Date().timeIntervalSince1970 - 3599.95)
        let obsolete = harness.hookExpiryTimer
        receive(tool, at: Date().timeIntervalSince1970)
        expect(obsolete?.isValid == false && harness.hookExpiryTimer == nil, "hook change cancels an obsolete timer")
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        expect(harness.objectWillChange.count == 2, "cancelled expiry does not publish")
        receive(stop, at: Date().timeIntervalSince1970 - 59.95)
        let old = harness.hookExpiryTimer
        harness.settings.appearance.finishedMinutes = 2
        harness.publishHookExpiry()
        expect(old?.isValid == false, "retention change invalidates the old timer")
        expect((harness.hookExpiryTimer?.fireDate.timeIntervalSinceNow ?? 0) > 59, "retention change re-arms the later deadline")
        harness.hookExpiryTimer?.invalidate()
        print("OK one-shot expiry publication, cancellation and rescheduling without polling")
    }
}
