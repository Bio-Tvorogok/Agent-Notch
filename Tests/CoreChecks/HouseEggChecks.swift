import Foundation

struct HouseEggChecks {
    func calendar() {
        XCTAssertTrue(HouseEggs.Holidays(month: 12, day: 20).xmas)
        XCTAssertTrue(HouseEggs.Holidays(month: 1, day: 7).xmas)
        XCTAssertFalse(HouseEggs.Holidays(month: 1, day: 8).xmas)
        XCTAssertTrue(HouseEggs.Holidays(month: 1, day: 1).newYear)
        XCTAssertTrue(HouseEggs.Holidays(month: 10, day: 25).halloween)
        XCTAssertFalse(HouseEggs.Holidays(month: 10, day: 24).halloween)
        XCTAssertTrue(HouseEggs.Holidays(month: 2, day: 14).valentine)
        XCTAssertTrue(HouseEggs.Holidays(month: 4, day: 1).fools)
    }
    func phases() {
        let b = HouseBehaviour(random: { 0.4 })
        let e = HouseEggs(behaviour: b)
        let sp = HouseSprite(id: "a", room: "__roof", point: [5,4,0]); sp.alpha = 1; sp.state = "done"
        b.sim.sprites.append(sp)
        XCTAssertTrue(e.trigger("ufo", at: 0))
        e.step(at: 4200)
        XCTAssertEqual(e.ufo?.lift, 16)
        XCTAssertEqual(e.ufo?.beam, 1)
        XCTAssertTrue(sp.frozen)
        e.step(at: 7401)
        XCTAssertFalse(sp.frozen)
        e.step(at: 10401)
        XCTAssertNil(e.ufo)
        XCTAssertTrue(e.trigger("party", at: 0))
        e.step(at: 59999); XCTAssertTrue(e.party)
        e.step(at: 60000); XCTAssertFalse(e.party)
    }
    func replacementAndCounting() {
        let b = HouseBehaviour(random: { 0.4 })
        let eggs = HouseEggs(behaviour: b)
        let a = HouseSprite(id: "a", room: "__roof", point: [5,4,0])
        let c = HouseSprite(id: "c#fall", room: "__roof", point: [6,4,0])
        for sp in [a,c] { sp.alpha = 1; sp.state = "done"; b.sim.sprites.append(sp) }
        c.behaviour.agent = HouseAgentRow(id: "c", state: "done")
        eggs.saved.count = 99
        let cal = Calendar.current, d = Date(), dc = cal.dateComponents([.year,.month,.day], from: d)
        eggs.saved.seenDay = "\(dc.year!)-\(dc.month!)-\(dc.day!)"
        eggs.step(at: 0)
        XCTAssertEqual(eggs.saved.gold, ["c"])
        XCTAssertEqual(eggs.saved.ids, ["c"])
        XCTAssertTrue(c.eggs.golden)
        let fresh = HouseSprite(id: "fresh", room: "__roof", point: [4,4,0])
        XCTAssertFalse(fresh.eggs.golden)
        XCTAssertFalse(fresh.eggs.seen)
        XCTAssertTrue(eggs.trigger("ufo", at: 0))
        eggs.step(at: 4000); XCTAssertTrue(a.frozen)
        a.alpha = 0
        XCTAssertTrue(eggs.trigger("ufo", at: 4100))
        XCTAssertFalse(a.frozen)
        eggs.step(at: 4200); XCTAssertTrue(c.frozen)
    }
    func clicksAndIdle() {
        let b = HouseBehaviour(random: { 0.4 }), eDate = Date(timeIntervalSince1970: 1_792_080_000)
        let e = HouseEggs(behaviour: b); e.date = { eDate }
        e.sky(at: 0)
        XCTAssertFalse(e.isMoving(at: 0))
        e.sun = [10,10]
        XCTAssertTrue(e.click(x: 10, y: 10, at: 0, overHouse: false))
        XCTAssertEqual(e.shadesUntil, 60000)
        XCTAssertFalse(e.isMoving(at: 100))
        e.clouds = [[100,50,40]]
        XCTAssertTrue(e.click(x: 110, y: 50, at: 0, overHouse: false))
        XCTAssertTrue(e.isMoving(at: 100))
        e.sky(at: 5001)
        XCTAssertFalse(e.isMoving(at: 5001))
    }
}
