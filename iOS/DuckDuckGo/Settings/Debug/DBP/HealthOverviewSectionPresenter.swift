//
//  HealthOverviewSectionPresenter.swift
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

import Foundation
import UIKit
import BackgroundTasks
import DataBrokerProtectionCore
import DataBrokerProtection_iOS

struct HealthOverviewRowViewModel {
    let title: String
    let detail: String?
    let subtitle: String?
    let style: DataBrokerProtectionDebugViewController.CellType
    let textColor: UIColor?
    let accessoryText: String?

    init(title: String,
         detail: String? = nil,
         subtitle: String? = nil,
         style: DataBrokerProtectionDebugViewController.CellType = .rightDetail,
         textColor: UIColor? = nil,
         accessoryText: String? = nil) {
        self.title = title
        self.detail = detail
        self.subtitle = subtitle
        self.style = style
        self.textColor = textColor
        self.accessoryText = accessoryText
    }
}

struct RunPrerequisitesStatus: Equatable {
    let hasAccount: Bool
    let hasEntitlement: Bool
    let hasProfile: Bool
}

enum HealthOverviewState {
    case loading
    case prerequisitesNotMet(RunPrerequisitesStatus)
    case ready(HealthOverviewMetrics)
}

struct HealthOverviewMetrics {
    typealias OperationSummary = (total: Int, stalled: Int, totalByBroker: [String: Int], stalledByBroker: [String: Int])

    struct BackgroundTaskStatus {
        let isScheduled: Bool
        let earliestRunDate: Date?
    }

    struct OperationMetrics {
        let count: Int
        let recentCount: Int
        let lastRunDate: Date?
        let upcomingRunDate: Date?
    }

    let backgroundTaskStatus: BackgroundTaskStatus
    let extractedProfilesCount: Int
    let extractedProfilesBreakdown: String?
    let optOutOperations: OperationMetrics
    let optOutWeeklySummary: OperationSummary
    let scanOperations: OperationMetrics
    let scanWeeklySummary: OperationSummary
    let optOutAttemptsCount: Int
    let optOutAttemptsBreakdown: String?
    let backgroundTaskSessionMetrics: BackgroundTaskSessionMetrics
    let backgroundTaskLastSession: BackgroundTaskSessionMetrics.Session?
}

final class HealthOverviewSectionPresenter {
    private static let cutOff = Date().daysAgo(7)

    private weak var runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
    private weak var debuggingDelegate: DBPIOSInterface.DebuggingDelegate?
    private weak var databaseDelegate: DBPIOSInterface.DatabaseDelegate?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?,
         debuggingDelegate: DBPIOSInterface.DebuggingDelegate?,
         databaseDelegate: DBPIOSInterface.DatabaseDelegate?) {
        self.runPrerequisitesDelegate = runPrerequisitesDelegate
        self.debuggingDelegate = debuggingDelegate
        self.databaseDelegate = databaseDelegate
    }

    func refreshStateIfNeeded(from currentState: HealthOverviewState? = nil) async -> HealthOverviewState {
        guard let runPrerequisitesDelegate else { return .loading }

        guard await runPrerequisitesDelegate.validateRunPrerequisites() else {
            let status = await RunPrerequisitesStatus(debuggingDelegate: debuggingDelegate, runPrerequisitesDelegate: runPrerequisitesDelegate)
            return .prerequisitesNotMet(status)
        }

        let hasScheduledBackgroundTask = await debuggingDelegate?.hasScheduledBackgroundTask ?? false
        let earliestRunDate = hasScheduledBackgroundTask ? await fetchEarliestBackgroundTaskRunDate() : nil
        let metrics = await buildMetrics(hasScheduledBackgroundTask: hasScheduledBackgroundTask,
                                         earliestRunDate: earliestRunDate)

        return .ready(metrics)
    }

    func rows(for state: HealthOverviewState) -> [HealthOverviewRowViewModel] {
        switch state {
        case .loading:
            return [HealthOverviewRowViewModel(title: "Loading...")]
        case .prerequisitesNotMet(let status):
            return [
                HealthOverviewRowViewModel(title: "Subscription Account", detail: status.hasAccount ? "✅" : "❌"),
                HealthOverviewRowViewModel(title: "PIR Entitlement", detail: status.hasEntitlement ? "✅" : "❌"),
                HealthOverviewRowViewModel(title: "Profile Saved In DB", detail: status.hasProfile ? "✅" : "❌")
            ]
        case .ready(let metrics):
            var rows: [HealthOverviewRowViewModel] = []

            if metrics.backgroundTaskStatus.isScheduled {
                rows.append(
                    HealthOverviewRowViewModel(title: "✅ PIR will run after device is locked and on power",
                                               subtitle: "Earliest run date: \(formattedDate(metrics.backgroundTaskStatus.earliestRunDate))",
                                               style: .subtitle)
                )
            } else {
                #if targetEnvironment(simulator)
                let message = "❌ Background jobs not supported in the simulator"
                #else
                let message: String
                if UIApplication.shared.backgroundRefreshStatus == .available {
                    message = "❌ Background the app to schedule PIR"
                } else {
                    message = "❌ Enable \"Background App Refresh\" in the app's privacy settings"
                }
                #endif
                rows.append(
                    HealthOverviewRowViewModel(title: message)
                )
            }

            rows.append(
                HealthOverviewRowViewModel(title: "Scan Operations",
                                           subtitle: subtitle(lastRun: metrics.scanOperations.lastRunDate,
                                                              upcoming: metrics.scanOperations.upcomingRunDate,
                                                              count: metrics.scanOperations.recentCount),
                                           style: .subtitle,
                                           accessoryText: "\(metrics.scanOperations.count)")
            )

            rows.append(
                HealthOverviewRowViewModel(title: "Extracted Profiles",
                                           subtitle: metrics.extractedProfilesBreakdown,
                                           style: .subtitle,
                                           accessoryText: "\(metrics.extractedProfilesCount)")
            )

            rows.append(
                HealthOverviewRowViewModel(title: "Opt-Out Operations",
                                           subtitle: subtitle(lastRun: metrics.optOutOperations.lastRunDate,
                                                              upcoming: metrics.optOutOperations.upcomingRunDate,
                                                              count: metrics.optOutOperations.recentCount),
                                           style: .subtitle,
                                           accessoryText: "\(metrics.optOutOperations.count)")
            )

            rows.append(
                HealthOverviewRowViewModel(title: "Opt-Out Attempts (last 7 days)",
                                           subtitle: metrics.optOutAttemptsBreakdown,
                                           style: .subtitle,
                                           accessoryText: "\(metrics.optOutAttemptsCount)")
            )

            let backgroundTaskSessionMetrics = metrics.backgroundTaskSessionMetrics
            let backgroundTaskSummary = """
Completed: \(backgroundTaskSessionMetrics.completed) · Orphaned: \(backgroundTaskSessionMetrics.orphaned) · Terminated: \(backgroundTaskSessionMetrics.terminated)
Duration: \(formattedDuration(backgroundTaskSessionMetrics.durationMinMs)) (min) · \(formattedDuration(backgroundTaskSessionMetrics.durationMedianMs)) (median) · \(formattedDuration(backgroundTaskSessionMetrics.durationMaxMs)) (max)
Last background task: \(formattedSession(metrics.backgroundTaskLastSession))
"""
            rows.append(
                HealthOverviewRowViewModel(title: "Background Task Events (last 7 days)",
                                           subtitle: backgroundTaskSummary,
                                           style: .subtitle,
                                           accessoryText: "\(backgroundTaskSessionMetrics.started)")
            )

            return rows
        }
    }

    // MARK: - Private helpers

    private func fetchEarliestBackgroundTaskRunDate() async -> Date? {
        #if targetEnvironment(simulator)
        return nil
        #else
        let identifier = DataBrokerProtectionIOSManager.backgroundTaskIdentifier
        let requests = await BGTaskScheduler.shared.pendingTaskRequests()
        return requests
            .filter { $0.identifier == identifier }
            .compactMap { $0.earliestBeginDate }
            .min()
        #endif
    }

    private func buildMetrics(hasScheduledBackgroundTask: Bool,
                              earliestRunDate: Date?) async -> HealthOverviewMetrics {
        let brokerData: [BrokerProfileQueryData] = (try? databaseDelegate?.getAllBrokerProfileQueryData()) ?? []
        let activeBrokerData = brokerData.filter { !$0.profileQuery.deprecated }

        let extractedProfilesCount = activeBrokerData.reduce(0) { $0 + $1.extractedProfiles.count }
        let scanJobs = activeBrokerData.map { $0.scanJobData }
        let optOutJobs = activeBrokerData.flatMap { $0.optOutJobData }
        let recentOptOutAttempts = (try? databaseDelegate?.getAllAttempts().filter { $0.lastStageDate >= Self.cutOff }) ?? []
        let recentBackgroundTaskEvents: [BackgroundTaskEvent] = (try? databaseDelegate?.getBackgroundTaskEvents(since: Self.cutOff)) ?? []
        let allBackgroundTaskEvents: [BackgroundTaskEvent] = (try? databaseDelegate?.getBackgroundTaskEvents(since: .distantPast)) ?? []

        return HealthOverviewMetrics(
            backgroundTaskStatus: .init(isScheduled: hasScheduledBackgroundTask,
                                        earliestRunDate: hasScheduledBackgroundTask ? earliestRunDate : nil),
            extractedProfilesCount: extractedProfilesCount,
            extractedProfilesBreakdown: activeBrokerData.displayString(),
            optOutOperations: optOutJobs.operationMetrics(from: activeBrokerData, using: .optOut),
            optOutWeeklySummary: StalledOperationCalculator.optOut.calculate(from: activeBrokerData),
            scanOperations: scanJobs.operationMetrics(from: activeBrokerData, using: .scan),
            scanWeeklySummary: StalledOperationCalculator.scan.calculate(from: activeBrokerData),
            optOutAttemptsCount: recentOptOutAttempts.count,
            optOutAttemptsBreakdown: recentOptOutAttempts.displayString(),
            backgroundTaskSessionMetrics: BackgroundTaskEvent.calculateSessionMetrics(
                from: recentBackgroundTaskEvents,
                orphanedThreshold: DataBrokerProtectionEventPixels.Consts.orphanedSessionThreshold,
                durationRange: DataBrokerProtectionEventPixels.Consts.minimumValidDurationMs...DataBrokerProtectionEventPixels.Consts.maximumValidDurationMs
            ),
            backgroundTaskLastSession: BackgroundTaskSessionMetrics.lastBackgroundTaskSession(from: allBackgroundTaskEvents)
        )
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return dateFormatter.string(from: date)
    }

    private func formattedDuration(_ milliseconds: Double) -> String {
        guard milliseconds > 0 else { return "-" }
        let seconds = milliseconds / 1000.0
        return String(format: "%.1fs", seconds)
    }

    private func formattedSession(_ session: BackgroundTaskSessionMetrics.Session?) -> String {
        guard let session else { return "-" }

        let startString = formattedDate(session.start.timestamp)
        let durationMs = formattedDuration(session.durationMs ?? 0)
        let status: String

        if session.isCompleted {
            status = "Completed (\(durationMs))"
        } else if session.isTerminated {
            status = "Terminated (\(durationMs))"
        } else {
            status = "Not yet completed"
        }

        return "\(startString) · \(status)"
    }

    private func subtitle(lastRun: Date?, upcoming: Date?, count: Int) -> String {
        return """
Last run: \(formattedDate(lastRun))
Upcoming: \(formattedDate(upcoming))
Last 7 days: \(count) operations
"""
    }
}

extension RunPrerequisitesStatus {
    init(debuggingDelegate: DBPIOSInterface.RunPrerequisitesDelegate?,
         runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate) async {
        self.hasAccount = (await debuggingDelegate?.isUserAuthenticated()) ?? false
        self.hasEntitlement = (try? await runPrerequisitesDelegate.meetsEntitlementRunPrequisite) ?? false
        self.hasProfile = (try? runPrerequisitesDelegate.meetsProfileRunPrequisite) ?? false
    }
}

private extension [AttemptInformation] {
    func displayString() -> String {
        guard !isEmpty else { return "-" }

        let counts = reduce(into: [String: Int]()) { partialResult, attempt in
            partialResult[attempt.dataBroker, default: 0] += 1
        }

        return HealthOverviewSectionPresenter.string(from: counts)
    }
}

private extension [BrokerProfileQueryData] {
    func displayString() -> String {
        let counts = reduce(into: [String: Int]()) { partialResult, brokerData in
            let count = brokerData.extractedProfiles.count
            guard count > 0 else { return }
            partialResult[brokerData.dataBroker.name, default: 0] += count
        }

        return HealthOverviewSectionPresenter.string(from: counts)
    }
}

extension HealthOverviewSectionPresenter {
    static func string(from breakdown: [String: Int]) -> String {
        guard !breakdown.isEmpty else { return "-" }
        return breakdown
            .sorted { ($0.value == $1.value) ? ($0.key < $1.key) : ($0.value > $1.value) }
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: " · ")
    }
}

private extension Array where Element: BrokerJobData {
    func operationMetrics(from profileQueryData: [BrokerProfileQueryData], using calculator: StalledOperationCalculator) -> HealthOverviewMetrics.OperationMetrics {
        let activeJobs = filter { !$0.isRemovedByUser }
        return HealthOverviewMetrics.OperationMetrics(
            count: activeJobs.count,
            recentCount: calculator.calculate(from: profileQueryData).total,
            lastRunDate: compactMap { $0.lastRunDate }.max(),
            upcomingRunDate: activeJobs.compactMap { $0.preferredRunDate }.min()
        )
    }
}
