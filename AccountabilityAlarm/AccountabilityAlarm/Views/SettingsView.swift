import SwiftUI

struct SettingsView: View {
    @AppStorage(Constants.bumpHapticKey) private var haptic = BumpHaptic.defaultValue.rawValue
    @AppStorage(Constants.bumpGlyphKey) private var glyph = "random"
    @AppStorage(Constants.bumpRemovalKey) private var removal = "random"
    @AppStorage(Constants.bumpConfettiPatternKey) private var pattern = "random"
    @AppStorage(Constants.bumpConfettiShapesKey) private var shapes = "random"
    @AppStorage(Constants.bumpFistWidthKey) private var fistWidth = 0.65
    @AppStorage(Constants.bumpLastRemovalKey) private var lastRemovalRaw = ""
    @Environment(AppState.self) private var appState

    @State private var showDemo = false
    @State private var demoChoice: BumpChoice?
    @State private var demoHaptic: BumpHaptic = .defaultValue
    @State private var demoWidth = 0.65

    var body: some View {
        VStack(spacing: 0) {
            LTopBar(left: "SETTINGS")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("HAPTIC") {
                        ForEach(BumpHaptic.allCases, id: \.rawValue) { preset in
                            SettingsRow(label: preset.label, selected: haptic == preset.rawValue,
                                        previewAction: { HapticService.shared.play(preset) }) {
                                haptic = preset.rawValue
                            }
                        }
                    }
                    section("HAND") {
                        pickerRows(selection: $glyph, items: BumpGlyph.allCases.map { ($0.rawValue, $0.label) })
                    }
                    section("REMOVAL ANIMATION") {
                        pickerRows(selection: $removal, items: FistRemoval.allCases.map { ($0.rawValue, $0.label) })
                    }
                    section("CONFETTI PATTERN") {
                        pickerRows(selection: $pattern, items: ConfettiPattern.allCases.map { ($0.rawValue, $0.label) })
                    }
                    section("CONFETTI SHAPES") {
                        pickerRows(selection: $shapes, items: ConfettiShapes.allCases.map { ($0.rawValue, $0.label) })
                    }
                    section("HAND SIZE") {
                        HStack(spacing: 12) {
                            Slider(value: $fistWidth, in: 0.50...0.75, step: 0.05)
                                .tint(L.Palette.fg)
                            Text("\(Int((fistWidth * 100).rounded()))%").kicker(L.Palette.fg)
                        }
                        .padding(.horizontal, L.Space.pageH)
                        .padding(.vertical, 12)
                    }

                    Button(action: tryIt) {
                        Text("Try it")
                            .font(L.Mono.font(10.5, weight: .semibold))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(L.Palette.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(L.Palette.fg)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, L.Space.pageH)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(L.Palette.bg.ignoresSafeArea())
        .foregroundStyle(L.Palette.fg)
        .onAppear { HapticService.shared.prepare() }
        .onChange(of: appState.activeSession) { _, s in
            if s != nil { showDemo = false }
        }
        .fullScreenCover(isPresented: $showDemo) {
            if let demoChoice {
                BumpStageView(sendOff: "Feet on the floor. Go get that run.",
                              fistWidthFraction: demoWidth, haptic: demoHaptic, choice: demoChoice,
                              snoozeLabel: "", isDemo: true,
                              onBump: { lastRemovalRaw = demoChoice.removal.rawValue }, onFinished: { showDemo = false }, onSnooze: {})
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func tryIt() {
        var r = BumpRandomizer()
        demoChoice = r.choose(glyphOverride: BumpGlyph(rawValue: glyph),
                              removalOverride: FistRemoval(rawValue: removal),
                              patternOverride: ConfettiPattern(rawValue: pattern),
                              shapesOverride: ConfettiShapes(rawValue: shapes),
                              lastRemoval: FistRemoval(rawValue: lastRemovalRaw))
        demoHaptic = BumpHaptic(rawValue: haptic) ?? .defaultValue
        demoWidth = fistWidth
        showDemo = true
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).kicker()
                .padding(.horizontal, L.Space.pageH)
                .padding(.top, 18)
                .padding(.bottom, 8)
            L.Palette.hair.frame(height: 1)
            content()
        }
    }

    @ViewBuilder
    private func pickerRows(selection: Binding<String>, items: [(String, String)]) -> some View {
        SettingsRow(label: "Random", selected: selection.wrappedValue == "random") {
            selection.wrappedValue = "random"
        }
        ForEach(items, id: \.0) { item in
            SettingsRow(label: item.1, selected: selection.wrappedValue == item.0) {
                selection.wrappedValue = item.0
            }
        }
    }
}

private struct SettingsRow: View {
    let label: String
    let selected: Bool
    var previewAction: (() -> Void)? = nil
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onSelect) {
                    HStack(spacing: 12) {
                        Circle()
                            .stroke(selected ? Color.clear : L.Palette.hair3, lineWidth: 1)
                            .background(Circle().fill(selected ? L.Palette.fg : Color.clear))
                            .frame(width: 8, height: 8)
                        Text(label)
                            .font(L.Mono.font(13))
                            .foregroundStyle(selected ? L.Palette.fg : L.Palette.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, L.Space.pageH)
                    .padding(.trailing, previewAction == nil ? L.Space.pageH : 0)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let previewAction {
                    Button(action: previewAction) {
                        Text("PREVIEW").kicker(L.Palette.accent)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, L.Space.pageH)
                }
            }
            L.Palette.hair.frame(height: 1)
        }
    }
}
