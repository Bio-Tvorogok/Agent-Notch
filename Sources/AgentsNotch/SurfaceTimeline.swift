import SwiftUI

extension EnvironmentValues {
    @Entry var surfaceActive = true
}

/// Keep a hidden panel mounted without leaving its periodic updates running.
@MainActor
final class SurfaceActivity: ObservableObject {
    @Published private(set) var active = false

    func setActive(_ value: Bool) {
        if active != value { active = value }
    }
}

struct ActiveSurface<Content: View>: View {
    @ObservedObject var activity: SurfaceActivity
    let content: Content

    init(activity: SurfaceActivity, @ViewBuilder content: () -> Content) {
        self.activity = activity
        self.content = content()
    }

    var body: some View {
        content.environment(\.surfaceActive, activity.active)
    }
}

/// A paused schedule supplies one frame; its content keeps the same view identity.
struct SurfaceSchedule: TimelineSchedule {
    let interval: TimeInterval
    let active: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        if active {
            return AnySequence(PeriodicTimelineSchedule(from: startDate, by: interval).entries(from: startDate, mode: mode))
        }
        return AnySequence([startDate])
    }
}

struct SurfaceTimeline<Content: View>: View {
    let interval: TimeInterval
    let content: (Date) -> Content
    @Environment(\.surfaceActive) private var active

    init(every interval: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        self.interval = interval
        self.content = content
    }

    var body: some View {
        TimelineView(SurfaceSchedule(interval: interval, active: active)) { context in
            content(context.date)
        }
    }
}
