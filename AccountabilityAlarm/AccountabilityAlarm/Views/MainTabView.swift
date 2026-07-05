import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var activeTab: LTab = .alarms

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
        .fullScreenCover(item: $appState.activeSession) { session in
            // .id(session.id): a re-trigger while a conversation is already
            // presented must rebuild the view (fresh view model, fresh
            // setup(), alarm silenced) rather than reuse the stale one.
            ConversationView(alarmId: session.alarmId)
                .id(session.id)
                .preferredColorScheme(.dark)
        }
    }
}
