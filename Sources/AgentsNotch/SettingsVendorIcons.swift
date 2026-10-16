import AppKit
import SwiftUI
import NotchCore

/// Everything the picker offers, in menu order. SF Symbols come from a separate search.
enum VendorIconChoices {
    static var themes: [VendorIcon] { ThemeID.withMarks.map { .theme($0) } }
    static var styles: [VendorIcon] { MarkStyle.allCases.map { .builtIn($0) } }

    static func name(_ icon: VendorIcon) -> String {
        switch icon {
        case .auto: SettingsText.name("auto")
        case .theme(let id): SettingsText.theme(id)
        case .builtIn(let style): SettingsText.name(style.rawValue)
        case .symbol(let symbol): symbol
        }
    }
}

/// One row per vendor: the current mark in every state, and a menu that shows every mark as a picture.
struct SettingsVendorIconRow: View {
    @ObservedObject var settings: AppSettings
    let vendor: Vendor
    @State private var symbolsOpen = false

    private var choice: Binding<VendorIcon> {
        Binding(get: { settings.vendorIcons[vendor] }, set: { settings.vendorIcons[vendor] = $0 })
    }
    private var vendorName: String { vendor == .claude ? SettingsText.claude : SettingsText.codex }

    var body: some View {
        HStack(spacing: 12) {
            VendorIconStateStrip(vendor: vendor)
            Text(vendorName)
            Spacer()
            VendorIconPopUp(settings: settings, vendor: vendor, choice: choice) { symbolsOpen = true }
                .fixedSize()
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $symbolsOpen) {
            VendorSymbolSheet(vendor: vendor, choice: choice) { symbolsOpen = false }
        }
    }
}

/// The chosen mark on a black wing, in all four states, so a choice is judged by every state it will show.
struct VendorIconStateStrip: View {
    let vendor: Vendor
    var icon: VendorIcon? = nil
    private let states: [(AgentState, String)] = [(.working, "working"), (.waiting, "waiting"), (.error, "error"), (.done, "done")]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(states, id: \.1) { state, key in
                ResolvedVendorMark(vendor: vendor, state: state, isLight: false, size: state == .working ? 18 : 13,
                                   onDark: true, icon: icon)
                    .help(SettingsText.name(key))
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(Color.black, in: Capsule())
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((vendor == .claude ? SettingsText.claude : SettingsText.codex) + ", " + SettingsText.vendorIconPreview)
    }
}

/// A still picture of one candidate mark on the black wing, for menu items.
@MainActor
enum VendorIconImage {
    static func make(_ icon: VendorIcon, vendor: Vendor, settings: AppSettings, side: CGFloat = 22) -> NSImage {
        let view = ResolvedVendorMark(vendor: vendor, state: .working, isLight: false, size: side * 0.68, onDark: true, icon: icon)
            .frame(width: side, height: side)
            .background(Color.black, in: RoundedRectangle(cornerRadius: side * 0.24))
            .environmentObject(settings)
            .environment(\.surfaceActive, false)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: side, height: side))
        image.size = NSSize(width: side, height: side)
        return image
    }
}

/// A native pop-up button: one click opens every mark as a picture with its name, one click picks.
struct VendorIconPopUp: NSViewRepresentable {
    @ObservedObject var settings: AppSettings
    let vendor: Vendor
    @Binding var choice: VendorIcon
    let chooseSymbol: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.imagePosition = .imageLeading
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.choose = { choice = $0 }
        coordinator.chooseSymbol = chooseSymbol
        coordinator.current = choice
        // Rebuild only when something a picture or a label depends on changed.
        let key = [Loc.language.rawValue, settings.theme.rawValue, "\(settings.usesThemeMarks)",
                   settings.appearance.markStyle.rawValue, "\(choice)"].joined(separator: "|")
        guard key != coordinator.key else { return }
        coordinator.key = key
        button.setAccessibilityLabel((vendor == .claude ? SettingsText.claude : SettingsText.codex) + ", " + SettingsText.vendorIcon)
        let menu = NSMenu()
        coordinator.icons = []
        func add(_ icon: VendorIcon) {
            let item = NSMenuItem(title: VendorIconChoices.name(icon), action: nil, keyEquivalent: "")
            item.image = VendorIconImage.make(icon, vendor: vendor, settings: settings)
            item.image?.accessibilityDescription = item.title
            item.tag = coordinator.icons.count
            coordinator.icons.append(icon)
            menu.addItem(item)
        }
        add(.auto)
        menu.addItem(.sectionHeader(title: SettingsText.vendorIconThemes))
        VendorIconChoices.themes.forEach(add)
        menu.addItem(.sectionHeader(title: SettingsText.vendorIconStyles))
        VendorIconChoices.styles.forEach(add)
        menu.addItem(.separator())
        if case .symbol = choice { add(choice) }
        let more = NSMenuItem(title: SettingsText.moreSymbols, action: nil, keyEquivalent: "")
        more.tag = -1
        menu.addItem(more)
        button.menu = menu
        if let index = coordinator.icons.firstIndex(of: choice) { button.selectItem(withTag: index) }
    }

    @MainActor
    final class Coordinator: NSObject {
        var icons: [VendorIcon] = []
        var key = ""
        var current: VendorIcon = .auto
        var choose: (VendorIcon) -> Void = { _ in }
        var chooseSymbol: () -> Void = {}

        @objc func picked(_ sender: NSPopUpButton) {
            let tag = sender.selectedTag()
            if tag >= 0, tag < icons.count {
                choose(icons[tag])
            } else {
                // «More symbols…» is not a choice: the current one stays selected and the search opens.
                if let index = icons.firstIndex(where: { $0 == current }) { sender.selectItem(withTag: index) }
                chooseSymbol()
            }
        }
    }
}

/// SF Symbols by name, opened from the menu. Return picks an exact name outside the browsing list.
struct VendorSymbolSheet: View {
    let vendor: Vendor
    @Binding var choice: VendorIcon
    let close: () -> Void
    @State private var query = ""

    private var vendorName: String { vendor == .claude ? SettingsText.claude : SettingsText.codex }
    private var selected: String? {
        if case .symbol(let name) = choice { return name }
        return nil
    }
    private var results: [String] {
        var names = VendorSymbolCatalog.names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        let exact = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if VendorIcon.isValidSymbol(exact), !names.contains(exact) { names.insert(exact, at: 0) }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vendorName + " · SF Symbols").font(.headline)
            TextField(SettingsText.symbolSearch, text: $query, prompt: Text(SettingsText.symbolSearch))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if VendorIcon.isValidSymbol(name) { choice = .symbol(name); close() }
                }
                .accessibilityLabel(vendorName + ", " + SettingsText.symbolSearch)
            if results.isEmpty {
                Text(SettingsText.noSymbols).font(.caption).foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
                        ForEach(results, id: \.self) { name in
                            let on = selected == name
                            Button { choice = .symbol(name); close() } label: {
                                Image(systemName: name).font(.system(size: 16))
                                    .frame(maxWidth: .infinity).frame(height: 34)
                                    .background(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain).help(name)
                            .accessibilityLabel(vendorName + ", " + name)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button(SettingsText.cancel, action: close).keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 440, height: 400)
    }
}

/// Public symbol names only. Exact-name entry also accepts symbols outside this browsing list.
private enum VendorSymbolCatalog {
    static let names: [String] = {
        let base = """
        bolt star heart sparkles terminal command cpu memorychip desktopcomputer laptopcomputer display
        keyboard computermouse server.rack externaldrive internaldrive opticaldisc network globe cloud sun.max
        moon flame drop leaf tree camera photo video film music.note speaker.wave.2 bell mic headphones
        paperplane envelope tray archivebox folder doc book bookmark calendar clock timer stopwatch hourglass
        alarm gear gearshape wrench screwdriver hammer paintbrush pencil highlighter ruler scissors
        link paperclip pin tag flag map location compass scope eye eyeglasses lightbulb flashlight.on
        battery.100 plug power powerplug antenna.radiowaves.left.and.right wifi dot.radiowaves.left.and.right
        lock key shield checkmark.seal xmark.seal exclamationmark.triangle questionmark.circle info.circle
        person person.2 person.3 figure.walk hand.thumbsup hand.thumbsdown hand.raised hand.wave
        brain brain.head.profile face.smiling gamecontroller puzzlepiece trophy medal crown diamond
        circle square triangle hexagon octagon seal oval capsule rectangle app app.badge
        cube shippingbox cylinder cone pyramid house building.2 tent mountain.2 airplane car bus tram bicycle
        ferry sailboat fuelpump road.lanes speedometer gauge chart.bar chart.pie chart.xyaxis.line
        arrow.up arrow.down arrow.left arrow.right arrow.triangle.branch arrow.triangle.merge
        arrow.clockwise arrow.counterclockwise arrow.2.squarepath arrow.up.right.square
        plus minus multiply divide equal percent number function sum infinity curlybraces chevron.left.forwardslash.chevron.right
        checkmark xmark exclamationmark questionmark at a.circle b.circle c.circle x.circle
        cursorarrow cursorarrow.rays target wand.and.stars paintpalette swatchpalette square.stack layers
        list.bullet list.number text.alignleft text.bubble bubble.left bubble.left.and.bubble.right quote.bubble
        magnifyingglass binoculars safari point.3.connected.trianglepath waveform wave.3.right pulse
        stethoscope cross.case bandage pills cross vial testtube flask atom fan snowflake wind tornado rainbow
        pawprint hare tortoise bird fish ant ladybug lizard dog cat carrot cup.and.saucer mug fork.knife
        gift balloon party.popper birthday.cake ticket popcorn soccerball basketball baseball tennisball
        dumbbell football volleyball sportscourt shoeprints watchface applewatch iphone ipad macmini macpro.gen3
        """.split(whereSeparator: \.isWhitespace).map(String.init)
        return Array(Set(base.flatMap { [$0, $0 + ".fill"] })).filter(VendorIcon.isValidSymbol).sorted()
    }()
}

/// Snapshot only: an open pop-up menu drawn from the same pictures and names, since AppKit menus never draw offscreen.
struct VendorIconMenuDrawing: View {
    @ObservedObject var settings: AppSettings
    let vendor: Vendor

    var body: some View {
        let current = settings.vendorIcons[vendor]
        VStack(alignment: .leading, spacing: 0) {
            item(.auto, current)
            header(SettingsText.vendorIconThemes)
            ForEach(VendorIconChoices.themes, id: \.self) { item($0, current) }
            header(SettingsText.vendorIconStyles)
            ForEach(VendorIconChoices.styles, id: \.self) { item($0, current) }
            Divider().padding(.vertical, 4)
            Text(SettingsText.moreSymbols).font(.system(size: 13)).padding(.leading, 24).frame(height: 24)
        }
        .padding(5).frame(width: 230)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.97)).shadow(color: .black.opacity(0.25), radius: 12, y: 4))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 10).padding(.top, 6).frame(height: 22)
    }

    private func item(_ icon: VendorIcon, _ current: VendorIcon) -> some View {
        let on = icon == current
        return HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).opacity(on ? 1 : 0).frame(width: 12)
            Image(nsImage: VendorIconImage.make(icon, vendor: vendor, settings: settings))
            Text(VendorIconChoices.name(icon)).font(.system(size: 13))
            Spacer()
        }
        .padding(.leading, 6).frame(height: 26)
    }
}
