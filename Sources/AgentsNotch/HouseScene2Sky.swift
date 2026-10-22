import AppKit
import SpriteKit

/// The sky behind the house and the morning mist over it. The gradient and the sunrise glow are painted natively for any hour;
/// the backdrop, the sun/moon/stars and the clouds are the parts cut at the AMBK bucket hours: between two buckets the later
/// one fades in over the earlier (the clouds are the nearer bucket's).
extension HouseScene2 {
    func buildSkyNodes() {}

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
