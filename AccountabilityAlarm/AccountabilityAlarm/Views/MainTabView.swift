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
                }
            }
            .padding(.bottom, 50) // reserve room for the tab bar

            LTabBar(active: $activeTab)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $appState.showConversation) {
            if let alarmId = appState.activeAlarmId,
               let ring = appState.activeRing {
                ConversationView(alarmId: alarmId, initialRing: ring)
                    .preferredColorScheme(.dark)
            }
        }
    }
}
