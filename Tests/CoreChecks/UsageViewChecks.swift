import Foundation
#if canImport(NotchCore)
import NotchCore
#endif

struct UsageViewChecks {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func thresholds() {
        XCTAssertEqual(UsageView.limitTone(79.99), .grey)
        XCTAssertEqual(UsageView.limitTone(80), .amber)
        XCTAssertEqual(UsageView.limitTone(94.99), .amber)
        XCTAssertEqual(UsageView.limitTone(95), .red)
        XCTAssertEqual(UsageView.contextTone(69.99), .grey)
        XCTAssertEqual(UsageView.contextTone(70), .amber)
        XCTAssertEqual(UsageView.contextTone(89.99), .amber)
        XCTAssertEqual(UsageView.contextTone(90), .red)
    }
    func chips() {
        let limits = VendorLimits(vendor: .claude, windows: [
            LimitWindow(label: "5 ч", usedPercent: 42), LimitWindow(label: "неделя", usedPercent: 81.2)
        ], updatedAt: now)
        XCTAssertEqual(UsageView.tightest(limits), 81.2)
        XCTAssertEqual(UsageViewText.chip(limits), "Claude 81%")
        XCTAssertEqual(UsageViewText.chip(VendorLimits(vendor: .codex, windows: [], updatedAt: now)), "Codex —")
        XCTAssertEqual(UsageViewText.context(ContextUsage(usedTokens: 630_000, windowTokens: 1_000_000)), "контекст 63% из 1M")
        XCTAssertEqual(UsageViewText.context(ContextUsage(usedTokens: 140_000, windowTokens: 200_000)), "контекст 70% из 200K")
        XCTAssertEqual(UsageView.fraction(150), 1)
        XCTAssertEqual(UsageView.fraction(-1), 0)
        XCTAssertEqual(UsageView.fraction(.nan), 0)
    }
    func contextRefresh() {
        let agent = Agent(id: "a", vendor: .claude, title: "a", state: .working, project: "p", logPath: "/log")
        XCTAssertTrue(UsageView.contextSourceChanged(previous: nil, next: agent))
        XCTAssertFalse(UsageView.contextSourceChanged(previous: agent, next: agent))
        var changed = agent
        changed.title = "Другое название"
        XCTAssertFalse(UsageView.contextSourceChanged(previous: agent, next: changed))
        changed.logPath = "/other"
        XCTAssertTrue(UsageView.contextSourceChanged(previous: agent, next: changed))
        changed = agent; changed.vendor = .codex
        XCTAssertTrue(UsageView.contextSourceChanged(previous: agent, next: changed))
    }
    func resets() {
        XCTAssertEqual(UsageViewText.reset(nil, now: now), "время сброса неизвестно")
        XCTAssertEqual(UsageViewText.reset(now, now: now), "сброс сейчас")
        XCTAssertEqual(UsageViewText.reset(now.addingTimeInterval(-60), now: now), "сброс сейчас")
        XCTAssertEqual(UsageViewText.reset(now.addingTimeInterval(30), now: now), "сброс через 1 мин")
        XCTAssertEqual(UsageViewText.reset(now.addingTimeInterval(120), now: now), "сброс через 2 мин")
        XCTAssertEqual(UsageViewText.reset(now.addingTimeInterval(7200), now: now), "сброс через 2 ч")
        XCTAssertEqual(UsageViewText.reset(now.addingTimeInterval(9000), now: now), "сброс через 2 ч 30 мин")
        XCTAssertEqual(UsageViewText.reset(now.addingTimeInterval(172800), now: now), "сброс через 2 д")
    }
}
