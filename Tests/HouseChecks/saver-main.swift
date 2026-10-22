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
        print("OK saver activity policy")
    }
}
