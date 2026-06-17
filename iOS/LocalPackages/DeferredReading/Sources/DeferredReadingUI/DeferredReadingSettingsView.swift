import DeferredReadingCore
import DesignResourcesKit
import SwiftUI

public struct DeferredReadingSettingsView: View {

    @ObservedObject private var settingsController: DeferredReadingSettingsController

    public init(settingsController: DeferredReadingSettingsController) {
        self.settingsController = settingsController
    }

    public var body: some View {
        List {
            Section("Quiet Period") {
                Picker("Quiet Period", selection: quietPeriodBinding) {
                    ForEach(DeferredReadingQuietPeriod.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            if settingsController.quietPeriod != .never {
                Section("Reminder Time") {
                    DatePicker(
                        "Time",
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Deferred Reading")
        .listStyle(.insetGrouped)
        .background(Color(designSystemColor: .background))
    }

    private var quietPeriodBinding: Binding<DeferredReadingQuietPeriod> {
        Binding(
            get: { settingsController.quietPeriod },
            set: { settingsController.setQuietPeriod($0) }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: { settingsController.reminderDate },
            set: { settingsController.setReminderTime($0) }
        )
    }
}
