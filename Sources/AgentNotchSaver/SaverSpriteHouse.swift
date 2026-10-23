import AppKit
import NotchCore
import SpriteKit

/// The screen saver's SpriteKit house: HouseScene2 over the atlas in the bundle, fed from the snapshot the app writes. Nothing covers a
/// saver, so the insets are zero; there is no pointer and no growth store (the saver is another process: rooms start unbuilt-up
/// and grow with the deliveries it sees). The scene rests when the saver is not on screen.
final class SaverSpriteHouse {
    let view: SKView
    let scene: HouseScene2
    private let behaviour: HouseBehaviour
    private var agents = ""

    /// nil when the atlas or the screen cannot draw it; the saver then shows a dark frame. The atlas draws the autumn islands house,
    /// whatever the snapshot's layout or the month.
    init?(size: CGSize, scale: CGFloat, atlas: URL, snapshot: HouseSnapshot, onFailure: @escaping () -> Void) {
        let config = (try? JSONSerialization.jsonObject(with: Data(snapshot.config.utf8))) as? [String: Any] ?? [:]
        guard size.width > 0, size.height > 0 else { return nil }
        let themes = (config["themes"] as? [String: String] ?? [:]).map { HouseLayout.ThemeChoice(project: $0.key, theme: $0.value) }
        let canvas = HouseLayout.Canvas(width: Double(size.width), height: Double(size.height), dpr: Double(scale))
        behaviour = HouseBehaviour(seed: UInt32.random(in: 1...UInt32.max), layout: .islands, canvas: canvas, insets: .init(), themes: themes)
        if let rows = Self.rows(snapshot.agents) { behaviour.setAgents(rows) }
        agents = snapshot.agents
        let env = HouseSkyEnv(innerHeight: Double(size.height), insetBottom: 0)
        guard HousePainter.groundRaw(layout: behaviour.layout, env: env) >= 0 else { return nil }
        let unit = CGFloat(behaviour.layout.view.PXD / behaviour.layout.view.DPR)
        guard let scene = HouseScene2.load(from: atlas, layout: behaviour.layout, unit: unit, size: size), scene.missingParts() == nil else { return nil }
        scene.env = env
        scene.attach(behaviour)
        scene.followClock = true
        scene.onFailure = { DispatchQueue.main.async { onFailure() } }
        scene.onStall = { DispatchQueue.main.async { onFailure() } }
        scene.maxFps = snapshot.fps
        let view = SKView(frame: NSRect(origin: .zero, size: size))
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = snapshot.fps
        view.presentScene(scene)
        self.view = view
        self.scene = scene
    }

    static func rows(_ json: String) -> [HouseAgentRow]? { try? JSONDecoder().decode([HouseAgentRow].self, from: Data(json.utf8)) }

    /// A newer snapshot: only changes reach the scene.
    func apply(_ snapshot: HouseSnapshot) {
        if scene.maxFps != snapshot.fps { scene.maxFps = snapshot.fps }
        guard snapshot.agents != agents, let rows = Self.rows(snapshot.agents) else { return }
        agents = snapshot.agents
        scene.deliver(rows)
    }

    /// Drawn only while the saver is presented.
    func setActive(_ on: Bool) { if on { scene.wake() } else { scene.hide() } }
}
