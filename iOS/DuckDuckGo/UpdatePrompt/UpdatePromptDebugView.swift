//
//  UpdatePromptDebugView.swift
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

import Common
import Persistence
import SwiftUI
import UIKit

/// Fakes a newer App Store release so the update prompt's schedule can be checked without waiting for one.
struct UpdatePromptDebugView: View {

    private static let simulatedDaysAgo = [0, 2, 7, 14, 15]

    private let storage: any ThrowingKeyedStoring<UpdatePromptKeys>
    private let installedVersion = AppVersion.shared.versionNumber
    private let osVersion = UIDevice.current.systemVersion
    @State private var refresh = 0

    init(keyValueStore: ThrowingKeyValueStoring) {
        storage = keyValueStore.throwingKeyedStoring()
    }

    var body: some View {
        List {
            Section {
                ForEach(Self.simulatedDaysAgo, id: \.self) { days in
                    Button("Simulate newer release \(days) days ago") {
                        simulateRelease(daysAgo: days, minimumOSVersion: "15.0")
                    }
                }
                ForEach([UpdatePromptStep.second, .last], id: \.self) { step in
                    Button("Simulate step \(step.rawValue) due, step \(step.rawValue - 1) shown") {
                        simulateRelease(daysAgo: step.days, minimumOSVersion: "15.0", dueStep: step)
                    }
                }
                Button("Simulate release needing iOS 99") {
                    simulateRelease(daysAgo: 15, minimumOSVersion: "99.0")
                }
                Button("Reset update prompt state", role: .destructive) {
                    try? storage.removeValue(for: \.latestRelease)
                    try? storage.removeValue(for: \.state)
                    try? storage.removeValue(for: \.lastFetchDate)
                    refresh += 1
                }
            } footer: {
                Text("Needs the updatePrompt flag. The prompt shows on the next foreground once due, if no prompt cooldown is running: reset it with Reset Prompts Cooldown Period. A simulated release also holds off the daily fetch for 24 hours.")
            }

            Section("Current state") {
                row("Installed version", installedVersion)
                row("iOS version", osVersion)
                let release = try? storage.latestRelease
                row("Latest release", release.map { "\($0.version), \(format($0.releaseDate)), iOS \($0.minimumOSVersion)+" } ?? "None")
                let state = try? storage.state
                row("Clock start", state.map { format($0.clockStart) } ?? "Not started")
                row("Last shown", state?.lastShown.map { "Step \($0.step.rawValue), \(format($0.date))" } ?? "Never")
                row("Next step", nextStepDescription(release: release, state: state))
                row("Last fetch", (try? storage.lastFetchDate).map(format) ?? "Never")
            }
            .id(refresh)
        }
        .navigationTitle("Update Prompt")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func nextStepDescription(release: AppStoreRelease?, state: UpdatePromptState?) -> String {
        let evaluation = UpdatePromptSchedule.evaluate(installedVersion: installedVersion,
                                                       osVersion: osVersion,
                                                       release: release,
                                                       state: state,
                                                       now: Date())
        if let step = evaluation.step {
            return "Step \(step.rawValue), due now"
        }
        guard let state = evaluation.state else { return "None" }
        guard let next = state.lastShown.map({ $0.step.next }) ?? .first else { return "None, all reminders shown" }
        return "Step \(next.rawValue), not yet due"
    }

    /// With `dueStep`, the step before it is recorded as shown when it was due, so `dueStep` is due now.
    private func simulateRelease(daysAgo: Int, minimumOSVersion: String, dueStep: UpdatePromptStep? = nil) {
        let now = Date()
        let day: TimeInterval = 24 * 60 * 60
        let releaseDate = now.addingTimeInterval(-TimeInterval(daysAgo) * day)
        let release = AppStoreRelease(version: Self.nextMinorVersion(after: installedVersion),
                                      releaseDate: releaseDate,
                                      minimumOSVersion: minimumOSVersion)
        var state = UpdatePromptState(installedVersion: installedVersion, clockStart: releaseDate)
        if let dueStep, let previous = UpdatePromptStep(rawValue: dueStep.rawValue - 1) {
            state = state.recordingShown(previous, at: releaseDate.addingTimeInterval(TimeInterval(previous.days) * day))
        }
        try? storage.set(release, for: \.latestRelease)
        try? storage.set(state, for: \.state)
        try? storage.set(now, for: \.lastFetchDate)
        refresh += 1
    }

    private static func nextMinorVersion(after version: String) -> String {
        var components = version.split(separator: ".").compactMap { Int($0) }
        while components.count < 3 { components.append(0) }
        components[1] += 1
        components[2] = 0
        return components.map(String.init).joined(separator: ".")
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
