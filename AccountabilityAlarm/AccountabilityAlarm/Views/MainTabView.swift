import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var activeTab: LTab = .alarms
    @State private var showBumpDemo = false

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .bottom) {
            L.Palette.bg.ignoresSafeArea()

            Group {
                switch activeTab {
                case .alarms:  AlarmListView()
                case .history: HistoryView()
                case .debug:   LogView()
                }
            }
            .padding(.bottom, 50) // reserve room for the tab bar

            LTabBar(active: $activeTab)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--bump-demo") { showBumpDemo = true }
        }
        .fullScreenCover(isPresented: $showBumpDemo) {
            BumpStageView(sendOff: "Feet on the floor. Go get that run.", fistWidthFraction: 0.65,
                          haptic: .thudClick,
                          choice: { var r = BumpRandomizer(); return r.choose(glyphOverride: BumpGlyph(rawValue: UserDefaults.standard.string(forKey: Constants.bumpGlyphKey) ?? ""), removalOverride: nil, patternOverride: nil, shapesOverride: nil, lastRemoval: nil) }(),
                          snoozeLabel: "Snooze 3m", isDemo: false,
                          onBump: {}, onFinished: { showBumpDemo = false }, onSnooze: { showBumpDemo = false })
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $appState.activeSession) { session in
            // .id(session.id): a re-trigger while a conversation is already
            // presented must rebuild the view (fresh view model, fresh
            // setup(), alarm silenced) rather than reuse the stale one.
            ConversationView(alarmId: session.alarmId, isRehearsal: session.isRehearsal)
                .id(session.id)
                .preferredColorScheme(.dark)
        }
    }
}
