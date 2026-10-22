import AppKit
import SpriteKit

/// The sky behind the house and the morning mist over it. The gradient and the sunrise glow are painted natively for any hour;
/// the backdrop, the sun/moon/stars and the clouds are the parts cut at the AMBK bucket hours: between two buckets the later
/// one fades in over the earlier (the clouds are the nearer bucket's).
extension HouseScene2 {
    func buildSkyNodes() {}

    // MARK: painting off the main thread

    func paintInputs() -> HousePainter.Inputs {
        .init(light: light, hour: hour, clockHM: clockHM, colon: colon, clockMillis: clockMillis, layout: layout, env: env)
    }

    struct PaintResult {
        var live: [(SKTexture, CGPoint, CGSize)?]
        var sky: HousePainter.SkyBundle?
        var clockOnly: Bool
        var build = 0
        var timedOut = false
    }

    /// Paints the live images and the sky for the current time on the paint queue and swaps them in on the main thread. `sync` waits
    /// for it (the first build, a harness frame); a minute's refresh does not. `clockOnly` repaints just the clock faces.
    func repaint(sync: Bool, clockOnly: Bool = false) {
        painted = true
        let build = buildId, inp = paintInputs(), makers = liveItems.map { (clockOnly && !$0.clock) ? nil : $0.make }
        let painter = self.painter
        let work: () -> PaintResult = {
            painter.set(inp)
            func tex(_ img: CGImage) -> SKTexture { let t = SKTexture(cgImage: img); t.filteringMode = .nearest; return t }
            var live: [(SKTexture, CGPoint, CGSize)?] = []
            for m in makers { if let m, let r = m(painter) { live.append((tex(r.0), r.1, r.2)) } else { live.append(nil) } }
            let sky = clockOnly ? nil : painter.paintSky()
            // upload now, off the main thread, so the swap costs nothing
            var all: [SKTexture] = live.compactMap { $0?.0 }
            if let sky { all += sky.pieces.compactMap { $0.tex } + sky.clouds.map { $0.tex } }
            var timedOut = false
            if !all.isEmpty {
                let sem = DispatchSemaphore(value: 0)
                SKTexture.preload(all) { sem.signal() }
                timedOut = sem.wait(timeout: .now() + 5) == .timedOut
            }
            return PaintResult(live: live, sky: sky, clockOnly: clockOnly, build: build, timedOut: timedOut)
        }
        if sync { let r = paintQueue.sync(execute: work); apply(r) } else {
            paintQueue.async { [weak self] in
                let r = work()
                DispatchQueue.main.async { self?.apply(r) }
            }
        }
    }

    func apply(_ r: PaintResult) {
        if r.timedOut { NSLog("agents-notch: house textures did not preload in time"); (onStall ?? onFailure)?(); return }
        guard r.build == buildId else { return } // painted for a house that has been built again since
        let t0 = CACurrentMediaTime()
        for (i, item) in liveItems.enumerated() where i < r.live.count {
            guard let n = item.node else { continue }
            if let (t, p, sz) = r.live[i] {
                n.texture = t; n.size = sz; n.position = CGPoint(x: p.x, y: -p.y); n.isHidden = false
                lastLive[i] = (t, p, sz)
            } else if !(r.clockOnly && !item.clock) { n.isHidden = true }
        }
        if let b = r.sky { applySky(b) }
        onApply?((CACurrentMediaTime() - t0) * 1000)
    }

    func applySky(_ b: HousePainter.SkyBundle) {
        if b.reset { texCache.removeAll() }
        skyGroup.removeAllChildren()
        clouds = []; ants = []
        for pc in b.pieces {
            let n: SKSpriteNode
            if let c = pc.color {
                n = SKSpriteNode(color: NSColor(srgbRed: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255, blue: CGFloat(c[2]) / 255, alpha: 1), size: CGSize(width: pc.w, height: pc.h))
            } else {
                if let t = pc.tex { texCache[pc.key] = t }
                guard let t = texCache[pc.key] else { continue }
                n = SKSpriteNode(texture: t, size: CGSize(width: pc.w, height: pc.h))
            }
            n.anchorPoint = CGPoint(x: 0, y: 1); n.position = CGPoint(x: pc.x, y: -pc.y); n.zPosition = pc.z; n.alpha = CGFloat(pc.alpha)
            skyGroup.addChild(n)
            if let ph = pc.ant { ants.append((n, ph)) }
        }
        for c in b.clouds {
            let n = SKSpriteNode(texture: c.tex, size: CGSize(width: c.w, height: 20))
            n.anchorPoint = CGPoint(x: 0, y: 1); n.zPosition = -47_000 + CGFloat(c.i)
            skyGroup.addChild(n); clouds.append((c.i, n))
        }
        updateClouds()
    }

    func updateClouds() {
        let S = 2.0, W = Double(canvasW), H = Double(canvasH), gnd = Double(HousePainter.groundOf(layout: layout, env: env))
        for (i, n) in clouds {
            let x = HouseLight.round(((Double(i) * 131 * S + clockMillis * (0.004 + Double(i % 3) * 0.002) * S).truncatingRemainder(dividingBy: W + 80 * S)) - 60 * S)
            let y = HouseLight.round(8 * S + (Double(i) * 29 * S).truncatingRemainder(dividingBy: max(20, min(H * 0.3, gnd * 0.45))))
            n.position = CGPoint(x: Double(x), y: -Double(y - 10))
        }
        for (n, ph) in ants { n.isHidden = !((clockMillis / 1000 + ph).truncatingRemainder(dividingBy: 2.6) < 0.9) }
    }

    private func swatch(_ c: [Int], alpha: Double) -> SKSpriteNode {
        let n = SKSpriteNode(color: NSColor(srgbRed: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255, blue: CGFloat(c[2]) / 255, alpha: 1), size: CGSize(width: 1, height: 1))
        n.anchorPoint = CGPoint(x: 0, y: 1)
        n.alpha = CGFloat(alpha)
        return n
    }

    // MARK: mist

    static func scRnd(_ i: Double, _ k: Double) -> Double {
        let x = sin(i * 12.9898 + k * 78.233) * 43758.5453
        return x - floor(x)
    }

    /// 5 to 8 am, low over the ground (mistAmount; clear weather).
    var mistAmount: Double {
        let h = Double(clockHM.0) + Double(clockHM.1) / 60
        if h < 4.8 || h > 8.6 { return 0 }
        let k = h < 6 ? (h - 4.8) / 1.2 : h < 7 ? 1 : 1 - (h - 7) / 1.6
        return k * k * (3 - 2 * k) * (0.55 + 0.45 * Self.scRnd(Double(day), 3))
    }

    func buildMist() {
        let z = topZ + 40
        mistBands = (0..<8).map { _ in
            let n = swatch([255, 255, 255], alpha: 0); n.zPosition = z; root.addChild(n); return n
        }
        mistWisps = (0..<7).map { i in
            let a = swatch([255, 255, 255], alpha: 0), b = swatch([255, 255, 255], alpha: 0)
            a.zPosition = z + 1; b.zPosition = z + 1
            root.addChild(a); root.addChild(b)
            return (a, b, i)
        }
    }

    func refreshMist() {
        let f = mistAmount, S = 2.0
        let W = Double(canvasW), H = Double(canvasH), top = Double(HouseLight.round(H * 0.48)), n = 8.0
        let sk = light.skyBottom, hz = [0xee, 0xf0, 0xf6]
        let c = (0..<3).map { HouseLight.round(Double(sk[$0]) + Double(hz[$0] - sk[$0]) * 0.45) }
        let color = NSColor(srgbRed: CGFloat(c[0]) / 255, green: CGFloat(c[1]) / 255, blue: CGFloat(c[2]) / 255, alpha: 1)
        for (i, node) in mistBands.enumerated() {
            node.isHidden = f < 0.02
            let y0 = top + Double(HouseLight.round((H - top) * Double(i) / n)), y1 = top + Double(HouseLight.round((H - top) * Double(i + 1) / n))
            node.color = color; node.position = CGPoint(x: 0, y: -y0); node.size = CGSize(width: W, height: y1 - y0)
            node.alpha = CGFloat(f * 0.72 * pow(Double(i + 1) / n, 1.5))
        }
        for (a, b, i) in mistWisps {
            a.isHidden = f < 0.02; b.isHidden = f < 0.02
            let w = Double((50 + (i * 37) % 60)) * S
            let x = Double(HouseLight.round(((Double(i) * 173 * S + clockMillis * 0.003 * S * Double(1 + i % 3)).truncatingRemainder(dividingBy: W + w)) - w))
            let y = Double(HouseLight.round(top + (H - top) * (0.06 + 0.12 * Double(i))))
            a.color = color; b.color = color
            a.alpha = CGFloat(f * 0.32); b.alpha = CGFloat(f * 0.32)
            a.position = CGPoint(x: x, y: -y); a.size = CGSize(width: w, height: 2 * S)
            b.position = CGPoint(x: x + 8 * S, y: -(y - S)); b.size = CGSize(width: w - 20 * S, height: S)
        }
    }
}
