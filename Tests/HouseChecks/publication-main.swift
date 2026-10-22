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
        publication.record(stop, ticket: nil, now: 100)
        func rows(_ t: Double) -> [Agent] { hooks.apply(to: [a], now: t, finishedRetention: 60, project: { _ in "house" }) }
        expect(publication.nextExpiry(agents: [a], hooks: hooks, now: 110, retention: 60) == 160, "hook stop schedules exact retention expiry without a poll")
        expect(publication.nextExpiry(agents: [a], hooks: hooks, now: 110, retention: 120) == 220, "retention preference changes move the deadline")
        expect(publication.update(rows(159)), "first effective snapshot publishes")
        expect(!publication.update(rows(159.5)), "unchanged hook output does not publish")
        expect(publication.update(rows(160)), "hook-ended turn publishes at retention expiry even with unchanged logs/hooks")
        expect(publication.nextExpiry(agents: [a], hooks: hooks, now: 160, retention: 60) == nil, "expired deadline does not re-arm")
        expect(!publication.update(rows(161)), "expired output stays quiet")
        hooks = HookState()
        let prompt = HookEvent(vendor: .claude, name: "Notification", sessionId: "session", notificationType: "permission_prompt", message: "Allow?")
        _ = hooks.receive(prompt, ticket: nil, now: 200)
        publication.record(prompt, ticket: nil, now: 200)
        expect(publication.nextExpiry(agents: [a], hooks: hooks, now: 201, retention: 60) == 3800, "prompt schedules its one-hour expiry")
        expect(rows(3799).first?.state == .waiting, "prompt fixture overlays working agent")
        expect(publication.update(rows(3799)), "new prompt publishes")
        expect(publication.update(rows(3800)), "one-hour prompt expiry publishes without a log change")
        expect(rows(3800).first?.state == .working, "expired prompt restores log state")
        expect(!publication.update(rows(3801)), "unchanged effective output remains quiet")
        expect(publication.nextExpiry(agents: [a], hooks: hooks, now: 3800, retention: 60) == nil, "expired prompt has no timer")
        hooks = HookState()
        _ = hooks.receive(prompt, ticket: nil, now: 5000)
        publication.record(prompt, ticket: nil, now: 5000)
        _ = hooks.receive(prompt, ticket: nil, now: 5100)
        publication.record(prompt, ticket: nil, now: 5100)
        expect(publication.nextExpiry(agents: [a], hooks: hooks, now: 5200, retention: 60) == 8700, "a replacement prompt cancels the old deadline")
        let tool = HookEvent(vendor: .claude, name: "PreToolUse", sessionId: "session")
        _ = hooks.receive(tool, ticket: nil, now: 5300)
        expect(publication.nextExpiry(agents: [a], hooks: hooks, now: 5300, retention: 60) == nil, "clearing a prompt cancels its timer")
        var b = a; b.id = "second"
        hooks = HookState()
        _ = hooks.receive(stop, ticket: nil, now: 6000)
        publication.record(stop, ticket: nil, now: 6000)
        let secondPrompt = HookEvent(vendor: .claude, name: "Notification", sessionId: "second", notificationType: "permission_prompt", message: "Allow?")
        _ = hooks.receive(secondPrompt, ticket: nil, now: 6010)
        publication.record(secondPrompt, ticket: nil, now: 6010)
        expect(publication.nextExpiry(agents: [a,b], hooks: hooks, now: 6020, retention: 60) == 6060, "earliest of multiple agents expires first")
        expect(publication.nextExpiry(agents: [a,b], hooks: hooks, now: 6060, retention: 60) == 9610, "next deadline follows the expired turn")
        print("OK hook retention, prompt deadlines and expiry publication")
    }
}
