import Foundation

/// The page's view (room/index.html: VIEW, viewTarget, zoomAt, panBy, glideTo, followTo, stepHome, stepCamera, resetView), ported without
/// the canvas: a zoom and a point (`at`, in the house's world pixels) the screen is centred on. Zooming makes the art pixels bigger, so the
/// whole view is the pair (zoom, at); `shift` says how far the house's art pixels have moved on the canvas of that view.
///
/// Times are the page's `performance.now()` in milliseconds; the host passes its own monotonic clock. Nothing here draws or reads the pointer.
public struct HouseCamera: Sendable {
    public struct Pose: Equatable, Sendable {
        public var zoom: Double
        public var at: [Double]
        public init(zoom: Double, at: [Double]) { self.zoom = zoom; self.at = at }
    }
    struct Glide: Sendable { var from: Pose, to: Pose; var t0, ms: Double }

    /// The numbers of the page's window: CSS size, device pixel ratio, the menu bar / Dock / icon-column insets, and the art pixel size at zoom 1.
    public let base, dpr, innerWidth, innerHeight, top, bottom, right: Double
    public let home: [Double]
    /// VIEW: where the camera is now.
    public private(set) var pose: Pose
    var glide: Glide?
    var follow: Pose?
    /// CAM.touched: the last time the viewer did anything to the view (the 30 s way back to the overview counts from it).
    public private(set) var touched = 0.0
    /// The page's class `on` on the overview button: the target is zoomed in.
    public private(set) var homeOn = false

    public static let maxZoom = 6.0
    public static let autoResetMs = 30_000.0

    public init(base: Double, dpr: Double, innerWidth: Double, innerHeight: Double, top: Double, bottom: Double, right: Double, home: [Double]) {
        self.base = base; self.dpr = dpr; self.innerWidth = innerWidth; self.innerHeight = innerHeight
        self.top = top; self.bottom = bottom; self.right = right; self.home = home
        pose = Pose(zoom: 1, at: home)
    }

    public init(layout: HouseLayout, innerWidth: Double, innerHeight: Double, insets: HouseLayout.Insets) {
        self.init(base: layout.view.base, dpr: layout.view.DPR, innerWidth: innerWidth, innerHeight: innerHeight,
                  top: insets.top, bottom: insets.bottom, right: insets.right, home: layout.view.home)
    }

    /// The same window with a new layout (a project joined): the view stays where it is when zoomed or zooming (a click or pinch in the frame of the relayout is kept), as the page's layout() leaves it.
    public func rebased(layout: HouseLayout) -> HouseCamera {
        var c = HouseCamera(base: layout.view.base, dpr: layout.view.DPR, innerWidth: innerWidth, innerHeight: innerHeight,
                            top: top, bottom: bottom, right: right, home: layout.view.home)
        if pose.zoom != 1 || target.zoom != 1 { c.pose = pose; c.glide = glide; c.follow = follow }
        c.touched = touched; c.homeOn = homeOn
        return c
    }

    /// True while the view is still going somewhere (the host keeps drawing).
    public var isMoving: Bool { glide != nil || follow != nil }
    /// viewTarget(): where the view is headed.
    public var target: Pose { glide?.to ?? follow ?? pose }

    // MARK: the canvas of a view

    /// applyView(): where the house's world origin lies on the canvas of this view, in art pixels (rooms' ox = wx + shift.x).
    public func shift(for p: Pose) -> (x: Double, y: Double) {
        let pxd = base * p.zoom
        let w = ceil(innerWidth * dpr / pxd), h = ceil(innerHeight * dpr / pxd)
        let lift = houseRound((top - bottom) / 2 * dpr / pxd), aside = houseRound(right / 2 * dpr / pxd)
        return (houseRound(w / 2 - aside - p.at[0]), houseRound(h / 2 + lift - p.at[1]))
    }

    /// How far the house has moved from the overview (zoom 1 at home), in art pixels of the view's own size.
    public func shiftFromHome(_ p: Pose) -> (x: Double, y: Double) {
        let a = shift(for: p), b = shift(for: Pose(zoom: 1, at: home))
        return (a.x - b.x, a.y - b.y)
    }

    /// CSS pixels of the window to the overview's canvas pixels (the coordinates the layout's rooms and sprites are in).
    public func toLayout(x: Double, y: Double, pose p: Pose? = nil) -> (x: Double, y: Double) {
        let p = p ?? pose, pxd = base * p.zoom, s = shiftFromHome(p)
        return (x * dpr / pxd - s.x, y * dpr / pxd - s.y)
    }

    // MARK: gestures

    /// zoomAt(factor, x, y): x, y in CSS pixels of the window.
    public mutating func zoomAt(_ factor: Double, x x0: Double, y y0: Double, now: Double) {
        touched = now
        let y = y0 - (top - bottom) / 2, x = x0 + right / 2
        let T = target, z = min(Self.maxZoom, max(1, T.zoom * factor))
        if z <= 1.001 { followTo(Pose(zoom: 1, at: home)); return }
        let P = base * T.zoom, P2 = base * z
        let wx = T.at[0] + x * dpr / P - ceil(innerWidth * dpr / P) / 2, wy = T.at[1] + y * dpr / P - ceil(innerHeight * dpr / P) / 2
        followTo(Pose(zoom: z, at: [wx - (x * dpr / P2 - ceil(innerWidth * dpr / P2) / 2), wy - (y * dpr / P2 - ceil(innerHeight * dpr / P2) / 2)]))
    }

    /// panBy(dx, dy): the scroll deltas of two fingers, in CSS pixels. Nothing to move at the overview.
    public mutating func panBy(dx: Double, dy: Double, now: Double) {
        touched = now
        let T = target
        if T.zoom == 1 { return }
        let P = base * T.zoom
        followTo(Pose(zoom: T.zoom, at: [T.at[0] - dx * dpr / P, T.at[1] - dy * dpr / P]))
    }

    public mutating func resetView(now: Double) { glideTo(Pose(zoom: 1, at: home), now: now) }

    public mutating func glideTo(_ to: Pose, now: Double, ms: Double = 420) {
        follow = nil; touched = now
        glide = Glide(from: pose, to: to, t0: now, ms: ms)
    }

    mutating func followTo(_ to: Pose) { glide = nil; follow = to }

    // MARK: stepping

    /// stepHome(): the overview button, and the way back after half a minute without touching the view.
    public mutating func stepHome(now: Double) {
        let zoomed = target.zoom > 1.01
        homeOn = zoomed
        if zoomed && glide == nil && follow == nil && now - touched > Self.autoResetMs { resetView(now: now) }
    }

    /// stepCamera(t, dt): one frame. Returns true when the pose changed.
    @discardableResult
    public mutating func step(now t: Double, dt: Double) -> Bool {
        stepHome(now: t)
        let before = pose
        if let G = glide {
            let u = min(1, max(0, (t - G.t0) / G.ms)), e = u < 0.5 ? 4 * u * u * u : 1 - pow(2 - 2 * u, 3) / 2
            let lf = log(G.from.zoom), lt = log(G.to.zoom)
            pose = Pose(zoom: exp(lf + (lt - lf) * e),
                        at: [G.from.at[0] + (G.to.at[0] - G.from.at[0]) * e, G.from.at[1] + (G.to.at[1] - G.from.at[1]) * e])
            if u >= 1 { glide = nil; pose = Pose(zoom: G.to.zoom, at: G.to.zoom == 1 ? home : G.to.at) }
        } else if let F = follow {
            let k = 1 - exp(-max(1, dt) / 60)
            let lz = log(pose.zoom)
            pose = Pose(zoom: exp(lz + (log(F.zoom) - lz) * k),
                        at: [pose.at[0] + (F.at[0] - pose.at[0]) * k, pose.at[1] + (F.at[1] - pose.at[1]) * k])
            if abs(log(F.zoom / pose.zoom)) < 0.002 && hypot(F.at[0] - pose.at[0], F.at[1] - pose.at[1]) < 0.3 {
                follow = nil; pose = Pose(zoom: F.zoom, at: F.zoom == 1 ? home : F.at)
            }
        }
        return pose != before
    }
}
