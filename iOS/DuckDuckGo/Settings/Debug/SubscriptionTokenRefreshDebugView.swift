//
//  SubscriptionTokenRefreshDebugView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import BackgroundTasks
import Combine
import Foundation
import Subscription
import SwiftUI

/// State and actions of the background token refresh debug screen.
@MainActor
final class SubscriptionTokenRefreshDebugViewModel: ObservableObject {

    /// A selectable interval. A nil value uses the keep-alive default.
    struct Preset: Hashable, Identifiable {
        let title: String
        let value: TimeInterval?
        var id: String { title }
    }

    /// Whether the background task is waiting to run.
    enum PendingTask: Equatable {
        case loading
        case none
        case scheduled(Date?)
    }

    static let maxRefreshTokenAgePresets: [Preset] = [
        Preset(title: "Default (15 days)", value: nil),
        Preset(title: "1 minute", value: .minutes(1)),
        Preset(title: "2 minutes", value: .minutes(2)),
        Preset(title: "5 minutes", value: .minutes(5)),
        Preset(title: "15 minutes", value: .minutes(15)),
        Preset(title: "1 hour", value: .hours(1)),
        Preset(title: "1 day", value: .days(1)),
    ]

    static let retryIntervalPresets: [Preset] = [
        Preset(title: "Default (6 hours)", value: nil),
        Preset(title: "30 seconds", value: 30),
        Preset(title: "1 minute", value: .minutes(1)),
        Preset(title: "5 minutes", value: .minutes(5)),
        Preset(title: "1 hour", value: .hours(1)),
    ]

    @Published var maxRefreshTokenAge: TimeInterval? {
        didSet { settings.maxRefreshTokenAgeOverride = maxRefreshTokenAge }
    }
    @Published var retryInterval: TimeInterval? {
        didSet { settings.retryIntervalOverride = retryInterval }
    }
    @Published private(set) var lastRun: SubscriptionTokenRefreshRun?
    @Published private(set) var pendingTask: PendingTask = .loading
    @Published private(set) var isFeatureEnabled = false
    @Published private(set) var isInternalUser = false

    private let settings: SubscriptionTokenRefreshDebugStoring
    private let notificationCenter: NotificationCenter
    private let readFeatureEnabled: () -> Bool
    private let readInternalUser: () -> Bool
    private let pendingRequests: () async -> [BGTaskRequest]
    private var didRunObserver: AnyCancellable?

    /// - Parameters:
    ///   - settings: Where the overrides are stored and the last run is read.
    ///   - notificationCenter: Where run requests are posted and finished runs are observed.
    ///   - isFeatureEnabled: Whether the `authBackgroundTokenRefresh` flag is on.
    ///   - isInternalUser: Whether the overrides apply.
    ///   - pendingRequests: The background task requests waiting to run.
    init(settings: SubscriptionTokenRefreshDebugStoring,
         notificationCenter: NotificationCenter = .default,
         isFeatureEnabled: @escaping () -> Bool,
         isInternalUser: @escaping () -> Bool,
         pendingRequests: @escaping () async -> [BGTaskRequest] = { await BGTaskScheduler.shared.pendingTaskRequests() }) {
        self.settings = settings
        self.notificationCenter = notificationCenter
        self.readFeatureEnabled = isFeatureEnabled
        self.readInternalUser = isInternalUser
        self.pendingRequests = pendingRequests
        maxRefreshTokenAge = settings.maxRefreshTokenAgeOverride
        retryInterval = settings.retryIntervalOverride
        didRunObserver = notificationCenter.publisher(for: .subscriptionTokenRefreshDidRun)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.reload() }
            }
    }

    /// Reads the flag, the last run and the pending background task again.
    func reload() async {
        isFeatureEnabled = readFeatureEnabled()
        isInternalUser = readInternalUser()
        lastRun = settings.lastRun
        let request = await pendingRequests().first { $0.identifier == SubscriptionTokenRefreshTask.taskIdentifier }
        pendingTask = request.map { .scheduled($0.earliestBeginDate) } ?? .none
    }

    /// Runs the keep-alive now, as a foreground run does. The screen reloads when the run finishes.
    func runNow() {
        notificationCenter.post(name: .subscriptionTokenRefreshDebugRunRequested, object: nil)
    }

    /// Removes both overrides and the record of the last run.
    func resetToDefaults() {
        maxRefreshTokenAge = nil
        retryInterval = nil
        settings.lastRun = nil
        lastRun = nil
    }
}

/// Debug screen to speed up the background token refresh and watch it run.
struct SubscriptionTokenRefreshDebugView: View {

    @ObservedObject var viewModel: SubscriptionTokenRefreshDebugViewModel

    var body: some View {
        Form {
            Section {
                row("Feature flag", viewModel.isFeatureEnabled ? "On" : "Off")
                row("Overrides apply", viewModel.isInternalUser ? "Yes (internal user)" : "No (not an internal user)")
                row("Pending background task", pendingTaskText)
            } header: {
                Text(verbatim: "Status")
            } footer: {
                Text(verbatim: "The flag is authBackgroundTokenRefresh. While it is off, a run does nothing and cancels the background task.")
            }

            Section {
                if let lastRun = viewModel.lastRun {
                    row("Finished", format(lastRun.date))
                    row("Trigger", lastRun.trigger.rawValue)
                    row("Outcome", lastRun.outcome)
                    row("Next check", lastRun.nextCheck.map(format) ?? "None, task cancelled")
                } else {
                    Text(verbatim: "No run recorded yet")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(verbatim: "Last run")
            }

            Section {
                Picker(selection: $viewModel.maxRefreshTokenAge) {
                    ForEach(SubscriptionTokenRefreshDebugViewModel.maxRefreshTokenAgePresets) { preset in
                        Text(verbatim: preset.title).tag(preset.value)
                    }
                } label: {
                    Text(verbatim: "Refresh token age")
                }
                Picker(selection: $viewModel.retryInterval) {
                    ForEach(SubscriptionTokenRefreshDebugViewModel.retryIntervalPresets) { preset in
                        Text(verbatim: preset.title).tag(preset.value)
                    }
                } label: {
                    Text(verbatim: "Retry after failure")
                }
            } header: {
                Text(verbatim: "Intervals")
            } footer: {
                Text(verbatim: "The token is refreshed once its refresh token is this old. Changes apply from the next run.")
            }

            Section {
                Button { viewModel.runNow() } label: { Text(verbatim: "Run now") }
                Button(role: .destructive) { viewModel.resetToDefaults() } label: { Text(verbatim: "Reset to defaults") }
            } footer: {
                Text(verbatim: """
                To watch it work: set the refresh token age to 2 minutes, then send the app to the background and wait. \
                Bringing the app back refreshes the token if it is due, and every run reschedules the background task. \
                iOS decides when the background task actually runs, usually while the device is charging, on Wi-Fi and idle. \
                To launch it right away, pause in the debugger and run:
                e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"\(SubscriptionTokenRefreshTask.taskIdentifier)"]
                Logs use the Subscription subsystem, category TokenKeepAlive.
                """)
            }
        }
        .navigationTitle(Text(verbatim: "Background Token Refresh"))
        .task { await viewModel.reload() }
        .refreshable { await viewModel.reload() }
    }

    private var pendingTaskText: String {
        switch viewModel.pendingTask {
        case .loading: return "Loading"
        case .none: return "None"
        case .scheduled(let date): return date.map(format) ?? "As soon as possible"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
