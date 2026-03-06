import SwiftUI
import SwiftData

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Alarm.hour) private var alarms: [Alarm]
    @State private var viewModel = AlarmListViewModel()
    @State private var alarmToEdit: Alarm?

    var body: some View {
        NavigationStack {
            List {
                if alarms.isEmpty {
                    ContentUnavailableView(
                        "No Alarms",
                        systemImage: "alarm",
                        description: Text("Tap + to create your first alarm")
                    )
                } else {
                    ForEach(alarms) { alarm in
                        AlarmRow(alarm: alarm) {
                            viewModel.toggleAlarm(alarm)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            alarmToEdit = alarm
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deleteAlarm(alarm, context: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingAddAlarm) {
                AlarmEditView()
            }
            .sheet(item: $alarmToEdit) { alarm in
                AlarmEditView(alarm: alarm)
            }
            .task {
                await viewModel.requestNotificationPermission()
            }
        }
    }
}
