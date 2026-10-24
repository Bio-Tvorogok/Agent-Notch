import Foundation
@main struct SaverChecks {
    static func main() {
        func check(_ result: Bool, _ message: String) { if !result { fatalError(message) } }
        let level = 1000
        check(SaverActivity.canDraw(running: true, attached: true, visible: true, occluded: false, preview: true, level: 0, saverLevel: level), "visible preview draws")
        check(!SaverActivity.canDraw(running: false, attached: true, visible: true, occluded: false, preview: false, level: level, saverLevel: level), "stopped saver never draws")
        check(!SaverActivity.canDraw(running: true, attached: false, visible: true, occluded: false, preview: false, level: level, saverLevel: level), "detached saver never draws")
        check(!SaverActivity.canDraw(running: true, attached: true, visible: false, occluded: false, preview: false, level: level, saverLevel: level), "hidden saver never draws")
        check(!SaverActivity.canDraw(running: true, attached: true, visible: true, occluded: true, preview: true, level: 0, saverLevel: level), "covered preview never draws")
        check(!SaverActivity.canDraw(running: true, attached: true, visible: true, occluded: false, preview: false, level: 0, saverLevel: level), "retired legacy saver window never draws")
        check(SaverActivity.canDraw(running: true, attached: true, visible: true, occluded: true, preview: false, level: level, saverLevel: level), "live mirrored saver ignores host occlusion")
        var state = SaverActivity.State()
        func sample(_ at: Double, _ visible: Bool, preview: Bool = false, running: Bool = true) -> SaverActivity.State {
            state = SaverActivity.sample(state, now: at, running: running, visible: visible, preview: preview)
            return state
        }
        check(sample(0, false).draw, "startup draws before the host reaches saver level")
        check(!sample(2, false).exitHost, "one missed poll cannot kill startup")
        check(sample(4, true).draw, "startup visibility recovers")
        check(sample(6, false).draw, "one level/visibility/detachment blip keeps drawing")
        check(!sample(10, false).exitHost, "four seconds of misses keep the host alive")
        check(sample(11, true).draw, "a visible sample resets the grace period")
        check(!sample(12, false).exitHost, "a later miss starts a fresh grace period")
        check(!sample(17.9, false).exitHost, "grace lasts six seconds")
        check(sample(18, false).exitHost && !state.draw, "sustained invisibility exits after six seconds")
        state = SaverActivity.State()
        check(!sample(0, false, preview: true).draw, "hidden preview pauses immediately")
        check(!sample(30, false, preview: true).exitHost, "hidden preview never exits its host")
        check(sample(32, true, preview: true).draw, "preview resumes when visible")
        check(!sample(34, true, preview: true, running: false).draw, "stopped preview does not draw")
        state = SaverActivity.State()
        check(sample(0, false).draw && sample(6, false).exitHost, "a host that never appears gets bounded startup grace")
        print("OK saver activity policy and visibility sequences")
    }
}
