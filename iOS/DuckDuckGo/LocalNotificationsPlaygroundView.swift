//
//  LocalNotificationsPlaygroundView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import Combine
import UserNotifications

struct LocalNotificationsPlaygroundView: View {
    @StateObject private var model = LocalNotificationsPlaygroundViewModel()

    var body: some View {
        List {
            Section {
                Text(model.notificationAuthStatus.description)
            } header: {
                Text(verbatim: "Authorization Status:")
            } footer: {
                switch model.notificationAuthStatus {
                case .granted:
                    Text(verbatim: "The user accepted receiving notifications when prompted or upon deciding to keep provisional notifications.")
                        .font(.caption)
                case .provisional:
                    Text(verbatim: "The system has automatically granted the app temporary permission to post noninterruptive notifications. They will be delivered silently in control")
                        .font(.caption)
                case .denied:
                    VStack(alignment: .leading)  {
                        Text(verbatim: "Ensure Notifications are Enabled in Settings")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button(
                            action: {
                                Task {
                                    await UIApplication.shared.openAppNotificationSettings()
                                }
                            },
                            label: {
                                Text(verbatim: "Open Settings...")
                            }
                        )
                    }
                case .notDetermined:
                    Text(verbatim: "The system will automatically prompt for permission when scheduling an alert notification. For provisional notifications, no prompt is shown, and the notification is delivered silently.")
                        .font(.caption)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Title")
                        .font(.caption)
                    TextField("Title", text: $model.notificationTitle)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Message")
                        .font(.caption)
                    TextField("Message", text: $model.notificationMessage)
                }
            } header: {
                Text(verbatim: "Content:")
            } footer: {
                HStack {
                    Button("Clear", action: model.clearAllContent)

                    Spacer()

                    Button("Default", action: model.fillDefaultContent)
                }
            }

            Section {
                Picker(
                    selection: $model.notificationType,
                    content: {
                        ForEach(LocalNotificationsPlaygroundViewModel.NotificationType.allCases, id: \.rawValue) { type in
                            Text(verbatim: type.description).tag(type)
                        }
                    },
                    label: {
                        Text(verbatim: "Type:")
                    }
                )

                Picker(
                    selection: $model.notificationSchedulingTime,
                    content: {
                        ForEach(1...10, id: \.self) { seconds in
                            Text("\(seconds)")
                        }
                    },
                    label: {
                        Text(verbatim: "Schedule in seconds:")
                    }
                )
            } header: {
                Text(verbatim: "Type:")
            } footer: {
                if model.notificationType == .provisional {
                    Text(verbatim: "Provisional notifications are not delivered when the app is in foreground. Put the app in background once the notification is scheduled.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Button(action: model.sendLocalNotification) {
                Text(verbatim: "Schedule \(model.notificationType.description) Notification in \(model.notificationSchedulingTime) seconds")
            }

        }
        .onAppear(perform: model.onAppear)
    }
}

@MainActor
private final class LocalNotificationsPlaygroundViewModel: ObservableObject {
    private static let testNotificationIdentifier = "com.duckduckgo.ios.testLocalNotification"

    private let center = UNUserNotificationCenter.current()
    
    private static let defaultTitle = "Tracker Blocked"
    private static let defaultBody = "We stopped 5 trackers from following you."

    @Published private(set) var isSchedulingNotification = false
    @Published var notificationTitle: String = defaultTitle
    @Published var notificationMessage: String = defaultBody
    @Published var notificationAuthStatus: NotificationAuthStatus = .notDetermined

    @Published var notificationType: NotificationType = .provisional
    @Published var notificationSchedulingTime: Int = 5

    private var cancellable: AnyCancellable?

    init() {
        bind()
    }

    func onAppear() {
        Task {
            await refreshAuthorizationSettings()
        }
    }

    func sendLocalNotification() {
        Task {
            let options: UNAuthorizationOptions = notificationType == .provisional ? [.provisional] : [.alert]
            do {
                guard try await center.requestAuthorization(options: options) else { return }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(notificationSchedulingTime), repeats: false)
                try await UNUserNotificationCenter.current().add(.make(identifier: Self.testNotificationIdentifier, title: notificationTitle, body: notificationMessage, trigger: trigger))
            } catch {
                print("~~~FAILED TO SEND NOTIFICATION TYPE: \(notificationType.description)")
            }
        }
    }
    
    func fillDefaultContent() {
        notificationTitle = Self.defaultTitle
        notificationMessage = Self.defaultBody
    }
    
    func clearAllContent() {
        notificationTitle = ""
        notificationMessage = ""
    }

    private func bind() {
        cancellable = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { _ in
                Task { [weak self] in
                    await self?.refreshAuthorizationSettings()
                }
            }
    }

    private func refreshAuthorizationSettings() async {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized:
            notificationAuthStatus = .granted
        case .provisional:
            notificationAuthStatus = .provisional
        case .denied:
            notificationAuthStatus = .denied
        case .notDetermined:
            notificationAuthStatus = .notDetermined
        default:
            break
        }
    }

    private func requestAuthorization(for option: UNAuthorizationOptions) async -> Bool {
        do {
            return try await center.requestAuthorization(options: [option])
        } catch {
            return false
        }
    }
}

extension LocalNotificationsPlaygroundViewModel {

    enum NotificationType: Int, CaseIterable {
        case provisional
        case alert

        var description: String {
            switch self {
            case .provisional:
                return "Provisional"
            case .alert:
                return "Alert"
            }
        }
    }

    enum NotificationAuthStatus: CustomStringConvertible {
        case granted
        case provisional
        case denied
        case notDetermined

        var description: String {
            switch self {
            case .granted:
                return "Granted"
            case .provisional:
                return "Provisional"
            case .denied:
                return "Denied"
            case .notDetermined:
                return "Not Determined"
            }
        }
    }
}

extension UNNotificationContent {

    fileprivate static func make(title: String, body: String) -> UNNotificationContent {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = title
        notificationContent.body = body
        return notificationContent
    }

}

extension UNNotificationRequest {

    static func make(identifier: String, title: String, body: String, trigger: UNNotificationTrigger? = nil) -> UNNotificationRequest {
        let content = UNNotificationContent.make(title: title, body: body)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

}

#Preview {
    LocalNotificationsPlaygroundView()
}
