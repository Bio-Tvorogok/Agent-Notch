import Foundation

/// The page's SKYLIFE (room/index.html drawSkyLife): flocks of birds, now and then a plane or a hot-air balloon crossing the sky.
/// This is the state and the schedule; the page draws and decides in one function and uses Math.random for both, so the same numbers are
/// drawn here in the same order (the seeded house stays in step with the page). The drawing is the scene's (HouseScene2SkyLife.swift).
/// Install with `HouseBehaviour.enableSkyLife()`; off by default, because the page's golden life fixtures exclude it.
public final class HouseSkyLife {
    public struct Flock { public var x, y, dir, v: Double; public var n: Int; public var seed: Double }
    public struct Plane { public var x, y, dir, v: Double }
    public struct Balloon { public var x, y, dir, v, seed: Double }
    public static let S = 2.0
    public var birds: [Flock] = [], plane: Plane?, balloon: Balloon?
    /// The page's `weather` ("clear" in the app) and DARK; the host sets them before a step.
    public var weather = "clear", dark = 0.0
    /// The canvas, in the page's pixels.
    public var width = 1440.0, height = 900.0
    private var next: (bird: Double, plane: Double, balloon: Double)?
    private var last = 0.0
    public init() {}

    /// Anything on the wing now (the scene draws it; it does not keep the house awake by itself, like the page).
    public var active: Bool { !birds.isEmpty || plane != nil || balloon != nil }

    /// One call of drawSkyLife(t) for the state: `t` is the frame's time, `random` the house's generator.
    public func step(_ t: Double, random: () -> Double) {
        let S = Self.S, dt = min(100, t - (last != 0 ? last : t)), W = width, H = height
        last = t
        if next == nil {
            let p = t + 50000 + random() * 100000
            let b = t + 80000 + random() * 160000
            next = (t + 3000, p, b)
        }
        if t > next!.bird {
            next!.bird = t + 12000 + random() * 25000
            if dark < 0.6 && weather != "rain" && birds.count < 3 {
                let dir: Double = random() < 0.5 ? 1 : -1
                let y = H * (0.06 + random() * 0.3)
                let v = (0.012 + random() * 0.008) * S
                let n = 3 + Int(floor(random() * 3))
                let seed = random() * 1000
                birds.append(.init(x: dir > 0 ? -30 * S : W + 30 * S, y: y, dir: dir, v: v, n: n, seed: seed))
            }
        }
        if t > next!.plane {
            next!.plane = t + 90000 + random() * 150000
            if plane == nil {
                let dir: Double = random() < 0.5 ? 1 : -1
                plane = .init(x: dir > 0 ? -20 * S : W + 20 * S, y: H * (0.05 + random() * 0.12), dir: dir, v: 0.02 * S)
            }
        }
        if t > next!.balloon {
            next!.balloon = t + 150000 + random() * 200000
            if balloon == nil && dark < 0.5 && weather != "rain" && weather != "snow" {
                let dir: Double = random() < 0.5 ? 1 : -1
                let y = H * (0.12 + random() * 0.22)
                balloon = .init(x: dir > 0 ? -12 * S : W + 12 * S, y: y, dir: dir, v: 0.004 * S, seed: random() * 9)
            }
        }
        birds = birds.compactMap { f in
            var f = f; f.x += f.dir * f.v * dt
            return (f.dir > 0 ? f.x < W + 60 * S : f.x > -60 * S) ? f : nil
        }
        if var p = plane {
            p.x += p.dir * p.v * dt
            plane = (p.dir > 0 ? p.x > W + 140 * S : p.x < -140 * S) ? nil : p
        }
        if var b = balloon {
            b.x += b.dir * b.v * dt
            balloon = (b.dir > 0 ? b.x > W + 20 * S : b.x < -20 * S) ? nil : b
        }
    }
}

extension HouseBehaviour {
    /// Runs the page's drawSkyLife schedule (and its random numbers) at the end of every scenes step. The hour/dark come from `life`.
    public func enableSkyLife() {
        let sky = skyLife
        stage3.drawSkyLife = { [unowned self, sky] t in
            sky.width = self.layout.view.width; sky.height = self.layout.view.height; sky.dark = self.life.dark
            sky.step(t, random: { self.sim.random() })
        }
    }
}
