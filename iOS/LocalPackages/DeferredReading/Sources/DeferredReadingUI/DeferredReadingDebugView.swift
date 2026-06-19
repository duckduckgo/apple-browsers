import DeferredReadingCore
import SwiftUI
import UserNotifications

public struct DeferredReadingDebugView: View {

    @ObservedObject private var controller: DeferredReadingController
    @State private var debugScheduledAt: Date?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isPromptPausedToday = false

    public init(controller: DeferredReadingController) {
        self.controller = controller
    }

    public var body: some View {
        List {
            Section("Reminder Status") {
                row(title: "Next scheduled reminder",
                    value: formatted(date: controller.nextScheduledReminderDate()) ?? "Not scheduled")
                row(title: "Unread deferred items", value: "\(controller.unreadCount)")
                row(title: "Prompt paused today", value: isPromptPausedToday ? "Yes" : "No")
            }

            Section("Prompt Pause") {
                Button("Reset Pause for Today") {
                    controller.resetPromptPause()
                    refreshStatus()
                }
            }

            Section("Debug Notification") {
                Button("Schedule test notification (+1 minute)") {
                    let now = Date()
                    debugScheduledAt = now.addingTimeInterval(60)
                    controller.scheduleDebugReminderNotificationInOneMinute(now: now)
                    refreshStatus()
                }

                row(title: "Notification permission",
                    value: notificationAuthorizationStatus.debugDescription)
                row(title: "Last debug schedule request",
                    value: formatted(date: debugScheduledAt) ?? "None")
            }
        }
        .navigationTitle("Deferred Reading Debug")
        .task {
            refreshStatus()
        }
    }

    @ViewBuilder
    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatted(date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func refreshStatus() {
        isPromptPausedToday = controller.isPromptPausedToday()
        Task {
            notificationAuthorizationStatus = await controller.debugNotificationAuthorizationStatus()
        }
    }
}

private extension UNAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }
}
