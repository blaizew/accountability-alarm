import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView {
            AlarmListView()
                .tabItem {
                    Label("Alarms", systemImage: "alarm")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .sheet(isPresented: $appState.showConversation) {
            if let alarmId = appState.activeAlarmId,
               let ring = appState.activeRing {
                ConversationView(alarmId: alarmId, initialRing: ring)
            }
        }
    }
}
