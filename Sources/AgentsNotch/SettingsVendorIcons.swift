import SwiftUI
import NotchCore

struct SettingsVendorIconRow: View {
    @ObservedObject var settings: AppSettings
    let vendor: Vendor
    @State private var query = ""

    private var choice: Binding<VendorIcon> {
        Binding(get: { settings.vendorIcons[vendor] }, set: { settings.vendorIcons[vendor] = $0 })
    }
    private var results: [String] {
        var names = VendorSymbolCatalog.names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        let exact = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if VendorIcon.isValidSymbol(exact), !names.contains(exact) { names.insert(exact, at: 0) }
        return Array(names.prefix(8))
    }
    private var selectedName: String? {
        if case .symbol(let name) = choice.wrappedValue { return name }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ResolvedVendorMark(vendor: vendor, state: .working, isLight: false, size: 18)
                    .environment(\.theme, settings.currentTheme)
                Text(vendor == .claude ? SettingsText.claude : SettingsText.codex)
                Spacer()
                Picker(SettingsText.vendorIcon, selection: choice) {
                    Text(SettingsText.name("auto")).tag(VendorIcon.auto)
                    ForEach(MarkStyle.allCases, id: \.self) { style in
                        Text(SettingsText.name(style.rawValue)).tag(VendorIcon.builtIn(style))
                    }
                    if let name = selectedName { Text(name).tag(VendorIcon.symbol(name)) }
                }.labelsHidden().frame(width: 200)
                Button(SettingsText.resetConfirmButton) { choice.wrappedValue = .auto; query = "" }
                    .controlSize(.small).disabled(choice.wrappedValue == .auto)
            }
            TextField(SettingsText.symbolSearch, text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if VendorIcon.isValidSymbol(name) { choice.wrappedValue = .symbol(name) }
                }
                .accessibilityLabel((vendor == .claude ? SettingsText.claude : SettingsText.codex) + ", " + SettingsText.symbolSearch)
            if results.isEmpty {
                Text(SettingsText.noSymbols).font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 6) {
                    ForEach(results, id: \.self) { name in
                        Button { choice.wrappedValue = .symbol(name) } label: {
                            Image(systemName: name).font(.system(size: 16))
                                .frame(maxWidth: .infinity).frame(height: 28)
                                .background(selectedName == name ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).help(name).accessibilityLabel(name)
                            .accessibilityAddTraits(selectedName == name ? .isSelected : [])
                    }
                }
            }
        }.padding(.vertical, 4)
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
