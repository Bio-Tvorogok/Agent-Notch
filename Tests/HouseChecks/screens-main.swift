import Foundation
@main struct ScreenChecks {
    static func main() {
        var state = RoomActivity()
        state.update(working: true, changed: true, now: 100)
        precondition(state.awake(at: 200), "working agents animate visible screens even if main page is covered")
        state.update(working: false, changed: true, now: 201)
        precondition(state.awake(at: 205), "movement can settle after a state change")
        precondition(!state.awake(at: 214), "covered main page cannot pin extra screens awake")
        state.update(working: false, changed: false, now: 220)
        precondition(!state.awake(at: 220), "unchanged polls never extend movement grace")
        state.update(working: true, changed: true, now: 230)
        precondition(RoomActivity.isActive(visible: true, awake: state.awake(at: 230)), "visible secondary screen wakes from agent state")
        precondition(!RoomActivity.isActive(visible: false, awake: state.awake(at: 230)), "each covered secondary screen stays paused")
        precondition(!RoomActivity.isActive(visible: true, awake: false), "settled secondary screen stops ambient animation")
        print("OK independent screen visibility and Swift awake state")
    }
}
