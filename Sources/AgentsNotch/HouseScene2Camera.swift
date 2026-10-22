import AppKit
import NotchCore
import SpriteKit

/// The view of the SpriteKit house: the page's VIEW (HouseCamera in NotchCore) applied to the scene. Zooming makes the art pixels
/// bigger, so the whole house is one node (`world`) scaled by `unit * zoom` and moved by how far the page's canvas would have moved
/// the rooms (`shiftFromHome`). The sky and the mist belong to the screen, not to the house: they keep the page's ground line
/// and only grow with the zoom (the page paints a new, bigger city for the smaller canvas; this one is the same city, magnified).
extension HouseScene2 {
    /// Gives the scene the view of its window; `nil` takes it away (the overview, no pointer).
    func installCamera(_ c: HouseCamera?) {
        houseCamera = c
        lastCameraNow = nil
        signHits = [:]
        if c != nil { buildHud() } else { hudNode?.removeFromParent(); hudNode = nil }
        applyCamera()
    }

    func applyCamera() {
        let p = houseCamera?.pose ?? HouseCamera.Pose(zoom: 1, at: [0, 0])
        let sh = houseCamera?.shiftFromHome(p) ?? (x: 0, y: 0)
        let Z = unit * CGFloat(p.zoom)
        world.setScale(Z)
        world.position = CGPoint(x: CGFloat(sh.x) * Z, y: size.height - CGFloat(sh.y) * Z)
        // sky and mist: same scale as the house, moved so that the ground line's middle stays where it is on the screen
        let k = 1 / p.zoom - 1, gnd = Double(HousePainter.groundOf(layout: layout, env: env))
        let pos = CGPoint(x: Double(canvasW) / 2 * k - sh.x, y: -gnd * k + sh.y)
        skyGroup.position = pos
        mistGroup.position = pos
    }

    // MARK: stepping

    /// One frame of the camera and of the hover (the page's stepCamera, then updateTip).
    func stepInteraction(frameMs: Double) {
        guard houseCamera != nil else { return }
        let now = nowMs()
        if houseCamera!.step(now: now, dt: frameMs) { applyCamera() }
        syncHud()
        if pointer != nil { updateHover() }
        if houseCamera!.homeOn, !houseCamera!.isMoving, autoResetTimer == nil { scheduleAutoReset() }
    }

    /// The way back after half a minute needs a frame to happen in: a resting house is woken for it.
    func scheduleAutoReset() {
        autoResetTimer?.invalidate()
        autoResetTimer = nil
        guard let c = houseCamera, c.target.zoom > 1.01 else { return }
        let wait = max(0.05, (c.touched + HouseCamera.autoResetMs - nowMs()) / 1000 + 0.1)
        autoResetTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoResetTimer = nil; self?.stir() }
        }
    }

    // MARK: the overview button

    private static let hudFont = NSFont.systemFont(ofSize: 13, weight: .semibold)

    func buildHud() {
        hudNode?.removeFromParent()
        let text = "⌂ Общий вид"
        let w = ceil((text as NSString).size(withAttributes: [.font: Self.hudFont]).width) + 24, h = 28.0
        let pill = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: h / 2)
        pill.fillColor = NSColor(srgbRed: 20 / 255, green: 16 / 255, blue: 32 / 255, alpha: 0.72)
        pill.strokeColor = .clear
        let label = SKLabelNode(text: text)
        label.fontName = Self.hudFont.fontName; label.fontSize = 13; label.fontColor = .white
        label.horizontalAlignmentMode = .center; label.verticalAlignmentMode = .center
        label.position = CGPoint(x: w / 2, y: h / 2)
        pill.addChild(label)
        pill.zPosition = 1_000_000
        pill.alpha = 0
        hudSize = CGSize(width: w, height: h)
        hudNode = pill
        addChild(pill)
        layoutHud()
    }

    func layoutHud() {
        guard let hud = hudNode else { return }
        hud.position = CGPoint(x: 16, y: size.height - 46 - hudSize.height)
    }

    /// #home.on: fades in while the view is zoomed in (the page's .25 s opacity and slide).
    func syncHud() {
        guard let hud = hudNode, let c = houseCamera else { return }
        let on = c.homeOn && hudEnabled
        if on == (hud.userData?["on"] as? Bool ?? false) { return }
        hud.userData = ["on": on]
        hud.removeAllActions()
        let y = size.height - 46 - hudSize.height
        hud.run(.group([.fadeAlpha(to: on ? 1 : 0, duration: 0.25), .moveTo(y: on ? y : y + 6, duration: 0.25)]))
    }

    /// The button's rectangle in window points (top-left origin), valid while it shows.
    var homeButtonRect: CGRect { CGRect(x: 16, y: 46, width: hudSize.width, height: hudSize.height) }
}
