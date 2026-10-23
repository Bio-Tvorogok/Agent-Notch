import AppKit
import SpriteKit

/// The extra screens' islets (the page's ISLETS / drawIslets): the baked islands floating in the sky of an extra screen (`extraScreen`).
/// Each is one sprite per light variant at its iso origin, `bob`bing on a sine, plus the camp's lamp glow after dark.
extension HouseScene2 {
    struct IsletNode { let node: SKSpriteNode; let lamp: SKSpriteNode?; let islet: HouseParts.Islet; let piece: HouseParts.IsletPiece }

    /// Called by rebuild() for an extra screen: the islets of the current light variant, above the sky and the city.
    func buildIslets(vi: Int) {
        isletNodes = []
        guard extraScreen, let list = parts.islets else { return }
        for it in list {
            guard vi < it.variants.count, let piece = it.variants[vi] else { continue }
            let n = sprite(piece.sprite, x: 0, y: 0, z: -46_000)
            var lamp: SKSpriteNode?
            if let l = it.lamp { let g = sprite(l.sprite, x: 0, y: 0, z: -45_990, blend: "add"); g.alpha = 0; lamp = g }
            isletNodes.append(IsletNode(node: n, lamp: lamp, islet: it, piece: piece))
        }
        updateIslets()
    }

    /// drawIslets: X = round(W * fx), Y = round(H * fy + sin(t / 2600 + i * 2.1) * 2 * S); the lamp glows at .1 + .25 * DARK while DARK > .3.
    func updateIslets() {
        let W = Double(canvasW), H = Double(canvasH), S = 2.0
        for it in isletNodes {
            let X = HouseLight.round(W * it.islet.fx), Y = HouseLight.round(H * it.islet.fy + sin(clockMillis / 2600 + it.islet.phase) * 2 * S)
            it.node.position = CGPoint(x: Double(X) + it.piece.x, y: -(Double(Y) + it.piece.y))
            if let l = it.islet.lamp, let g = it.lamp {
                let on = light.dark > l.from
                g.isHidden = !on
                g.alpha = on ? CGFloat(max(0, min(1, l.a + l.b * light.dark))) : 0
                g.position = CGPoint(x: Double(HouseLight.round(Double(X) + l.x)) - Double(l.r), y: -(Double(HouseLight.round(Double(Y) + l.y)) - Double(l.r)))
            }
        }
    }
}
