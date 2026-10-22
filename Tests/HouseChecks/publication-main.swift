import Foundation
import NotchCore
@main struct PublicationChecks {
    static func main() {
        func expect(_ v: Bool, _ why: String) { if !v { fatalError(why) } }
        var a = Agent(id: "session", vendor: .claude, title: "build", state: .working, project: "house", startedAt: 10)
        a.lastAt = 20
        var hooks = HookState()
        let stop = HookEvent(vendor: .claude, name: "Stop", sessionId: "session")
        _ = hooks.receive(stop, ticket: nil, now: 100)
        var publication = HookOutputPublication()
        func rows(_ t: Double) -> [Agent] { hooks.apply(to: [a], now: t, finishedRetention: 60, project: { _ in "house" }) }
        expect(publication.update(rows(159)), "first effective snapshot publishes")
        expect(!publication.update(rows(159.5)), "unchanged hook output does not publish")
        expect(publication.update(rows(160)), "hook-ended turn publishes at retention expiry even with unchanged logs/hooks")
        expect(!publication.update(rows(161)), "expired output stays quiet")
        hooks = HookState()
        let prompt = HookEvent(vendor: .claude, name: "Notification", sessionId: "session", notificationType: "permission_prompt", message: "Allow?")
        _ = hooks.receive(prompt, ticket: nil, now: 200)
        expect(rows(3799).first?.state == .waiting, "prompt fixture overlays working agent")
        expect(publication.update(rows(3799)), "new prompt publishes")
        expect(publication.update(rows(3800)), "one-hour prompt expiry publishes without a log change")
        expect(rows(3800).first?.state == .working, "expired prompt restores log state")
        expect(!publication.update(rows(3801)), "unchanged effective output remains quiet")
        print("OK hook retention and prompt-expiry publication")
    }
}
