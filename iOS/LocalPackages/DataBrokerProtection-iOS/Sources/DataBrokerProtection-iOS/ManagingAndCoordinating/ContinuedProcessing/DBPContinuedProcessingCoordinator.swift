//
//  DBPContinuedProcessingCoordinator.swift
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
import DataBrokerProtectionCore
import Foundation
import os.log

// MARK: - Coordinator Delegate (coordinator → manager)

protocol DBPContinuedProcessingDelegate: AnyObject {
    func coordinatorDidStartRun()
    func coordinatorDidFinishRun()
    func coordinatorIsReadyForScanOperations() async
    func coordinatorIsReadyForOptOutOperations()
    func coordinatorDidRequestStopOperations()
    func continuedProcessingScanJobTimeout() -> TimeInterval
    func makeContinuedProcessingOptOutPlan() throws -> DBPContinuedProcessingPlans.OptOutPlan
}

enum DBPContinuedProcessingEvent {
    case scanJobCompleted(DBPContinuedProcessingPlans.ScanJobID)
    case optOutJobCompleted(DBPContinuedProcessingPlans.OptOutJobID)
    case scanPhaseCompleted
    case optOutPhaseCompleted
}

// MARK: - Coordinator Protocol (manager → coordinator)

protocol DBPContinuedProcessingCoordinating: AnyObject, Sendable {
    func hasAttachedTask() async -> Bool
    func startInitialRun(scanPlan: DBPContinuedProcessingPlans.InitialScanPlan) async throws
    func didEmit(event: DBPContinuedProcessingEvent) async
}

// MARK: - Coordinator

@available(iOS 26.0, *)
actor DBPContinuedProcessingCoordinator {

    enum Phase {
        case initialScan
        case initialOptOut
    }

    private enum Constants {
        static let taskIdentifierPrefix = "dbp.continuedProcessing"
        static let taskTitle = "Personal Information Removal"
        static let heartbeatInterval: TimeInterval = 1.5
    }

    private weak var delegate: DBPContinuedProcessingDelegate?
    private let progressReporter: DBPContinuedProcessingProgressReporter

    private var taskIdentifier: String?
    private var phase: Phase?
    private var task: BGContinuedProcessingTask?
    private var heartbeatTask: Task<Void, Never>?

    func hasAttachedTask() -> Bool {
        task != nil
    }

    init(delegate: DBPContinuedProcessingDelegate,
         progressReporter: DBPContinuedProcessingProgressReporter? = nil) {
        self.delegate = delegate
        self.progressReporter = progressReporter ?? DBPContinuedProcessingProgressReporter()
    }

    // MARK: - Run Lifecycle

    /// Registers the continued task for a prepared scan plan and starts the initial scan phase.
    func startInitialRun(scanPlan: DBPContinuedProcessingPlans.InitialScanPlan) async throws {
        guard phase == nil else {
            Logger.dataBrokerProtection.error(
                "Continued processing: startInitialRun called while already active in phase \(String(describing: self.phase), privacy: .public) for run \(self.logRunIdentifier(), privacy: .public), ignoring"
            )
            return
        }

        Logger.dataBrokerProtection.log(
            "Continued processing: preparing initial run with \(scanPlan.scanCount, privacy: .public) scans"
        )
        let scanJobTimeout = delegate?.continuedProcessingScanJobTimeout() ?? .minutes(3)
        progressReporter.startInitialRun(plan: scanPlan,
                                         scanJobTimeout: scanJobTimeout,
                                         heartbeatInterval: Constants.heartbeatInterval)

        delegate?.coordinatorDidStartRun()

        do {
            try registerAndSubmitTask()
        } catch {
            finish(success: false)
            throw error
        }
        startHeartbeat()
        await startScanPhase()
    }

    /// Attaches the system-provided continued task and starts keeping its presentation in sync.
    func attach(task: BGContinuedProcessingTask) {
        self.task = task
        Logger.dataBrokerProtection.log(
            "Continued processing: attached task for run \(self.logRunIdentifier(), privacy: .public) in phase \(String(describing: self.phase), privacy: .public)"
        )
        task.expirationHandler = { [weak self] in
            Task { await self?.expire() }
        }

        refreshContinuedProcessingUI()
    }

    /// Stops continued-processing work when the system expires the task.
    func expire() {
        Logger.dataBrokerProtection.log(
            "Continued processing: task expired for run \(self.logRunIdentifier(), privacy: .public) in phase \(String(describing: self.phase), privacy: .public)"
        )
        delegate?.coordinatorDidRequestStopOperations()
        finish(success: false)
    }

    /// Tears down the continued task and reports final success to the system.
    private func finish(success: Bool) {
        Logger.dataBrokerProtection.log(
            "Continued processing: finishing run \(self.logRunIdentifier(), privacy: .public) success=\(success, privacy: .public) phase=\(String(describing: self.phase), privacy: .public)"
        )
        heartbeatTask?.cancel()
        heartbeatTask = nil

        if success {
            progressReporter.completeAll()
            refreshContinuedProcessingUI()
        }

        task?.setTaskCompleted(success: success)
        task = nil
        transition(to: nil)
        taskIdentifier = nil
        delegate?.coordinatorDidFinishRun()
    }

    // MARK: - Phases

    /// Transitions into the initial scan phase and signals the delegate to start scans.
    func startScanPhase() async {
        transition(to: .initialScan)
        Logger.dataBrokerProtection.log("Continued processing: starting scan phase for run \(self.logRunIdentifier(), privacy: .public)")
        await delegate?.coordinatorIsReadyForScanOperations()
    }

    /// Completes scan progress and either moves to initial opt-outs or finishes the run.
    func handleScanPhaseCompleted() async {
        progressReporter.completeScanPhase()
        refreshContinuedProcessingUI()
        Logger.dataBrokerProtection.log("Continued processing: scan phase completed for run \(self.logRunIdentifier(), privacy: .public)")

        guard let optOutPlan = try? delegate?.makeContinuedProcessingOptOutPlan() else {
            Logger.dataBrokerProtection.log("Continued processing: failed to load opt-out plan after scan phase for run \(self.logRunIdentifier(), privacy: .public)")
            finish(success: false)
            return
        }

        if optOutPlan.optOutCount == 0 {
            Logger.dataBrokerProtection.log("Continued processing: no initial opt-outs found after scan phase for run \(self.logRunIdentifier(), privacy: .public)")
            finish(success: true)
            return
        }

        Logger.dataBrokerProtection.log(
            "Continued processing: discovered \(optOutPlan.optOutCount, privacy: .public) initial opt-outs for run \(self.logRunIdentifier(), privacy: .public)"
        )
        await startOptOutPhase(optOutPlan: optOutPlan)
    }

    /// Transitions into the initial opt-out phase and signals the delegate to start opt-outs.
    func startOptOutPhase(optOutPlan: DBPContinuedProcessingPlans.OptOutPlan) async {
        transition(to: .initialOptOut) {
            self.progressReporter.enterOptOutPhase(plan: optOutPlan)
        }
        Logger.dataBrokerProtection.log("Continued processing: starting opt-out phase for run \(self.logRunIdentifier(), privacy: .public)")
        delegate?.coordinatorIsReadyForOptOutOperations()
    }

    /// Completes opt-out progress and finishes the continued-processing run.
    func handleOptOutPhaseCompleted() {
        progressReporter.completeOptOutPhase()
        refreshContinuedProcessingUI()
        Logger.dataBrokerProtection.log("Continued processing: opt-out phase completed for run \(self.logRunIdentifier(), privacy: .public)")
        finish(success: true)
    }

    // MARK: - Task Presentation

    /// Refreshes the system UI.
    private func refreshContinuedProcessingUI() {
        let snapshot = progressReporter.snapshot()
        task?.progress.totalUnitCount = max(snapshot.total, 1)
        task?.progress.completedUnitCount = min(snapshot.completed, max(snapshot.total, 1))

        let subtitle = switch phase {
        case .initialOptOut: progressReporter.optOutSubtitle
        default: progressReporter.scanSubtitle
        }
        task?.updateTitle(Constants.taskTitle, subtitle: subtitle)
    }

    // MARK: - Helpers

    /// Creates a unique task identifier, registers the handler, and submits the continued task request.
    private func registerAndSubmitTask() throws {
        let taskIdentifier = makeUniqueTaskIdentifier()
        self.taskIdentifier = taskIdentifier
        Logger.dataBrokerProtection.log("Continued processing: starting run \(self.logRunIdentifier(), privacy: .public) with task identifier \(taskIdentifier, privacy: .public)")
        try registerTaskHandler(identifier: taskIdentifier)
        try submitTaskRequest(identifier: taskIdentifier)
    }

    /// Keeps the system task alive by periodically advancing synthetic progress.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.heartbeatInterval))
                await self?.heartbeatTick()
            }
        }
    }

    private func heartbeatTick() {
        guard task != nil, phase != nil else { return }
        progressReporter.advanceHeartbeat()
        refreshContinuedProcessingUI()
    }

    /// Sets the active phase, runs any progress updates, and refreshes the system task UI.
    private func transition(to phase: Phase?, updateProgress: (() -> Void)? = nil) {
        self.phase = phase
        updateProgress?()
        refreshContinuedProcessingUI()
    }

    private func makeUniqueTaskIdentifier() -> String {
        "\(requiredBundleIdentifier()).\(Constants.taskIdentifierPrefix).\(UUID().uuidString)"
    }

    private func requiredBundleIdentifier() -> String {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            fatalError("Missing bundle identifier for continued processing task registration")
        }

        return bundleIdentifier
    }

    /// Returns a short log-friendly suffix derived from the full task identifier.
    private func logRunIdentifier() -> String {
        guard let taskIdentifier else { return "unknown" }
        return taskIdentifier.split(separator: ".").last.map(String.init) ?? taskIdentifier
    }

    /// Registers the continued task handler using the unique task identifier.
    private func registerTaskHandler(identifier taskIdentifier: String) throws {
        Logger.dataBrokerProtection.log(
            "Continued processing: registering task handler for identifier \(taskIdentifier, privacy: .public)"
        )

        let didRegister = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            Logger.dataBrokerProtection.log("Continued processing: task handler invoked for identifier \(task.identifier, privacy: .public)")
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                Logger.dataBrokerProtection.error("Continued processing: received non-continued task for identifier \(task.identifier, privacy: .public)")
                task.setTaskCompleted(success: true)
                return
            }

            Task { await self?.attach(task: continuedTask) }
        }

        guard didRegister else {
            Logger.dataBrokerProtection.error(
                "Continued processing: failed to register task handler for identifier \(taskIdentifier, privacy: .public)"
            )
            throw DBPContinuedProcessingError.taskHandlerRegistrationFailed
        }

        Logger.dataBrokerProtection.log(
            "Continued processing: successfully registered task handler for identifier \(taskIdentifier, privacy: .public)"
        )
    }

    /// Submits the continued task request that lets the system relaunch or continue the work.
    private func submitTaskRequest(identifier: String) throws {
        #if targetEnvironment(simulator)
        Logger.dataBrokerProtection.log("Continued processing: skipping task request submission on simulator for identifier \(identifier, privacy: .public)")
        return
        #else
        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                       title: Constants.taskTitle,
                                                       subtitle: progressReporter.scanSubtitle)
        request.strategy = .queue

        do {
            Logger.dataBrokerProtection.log("Continued processing: submitting task request for identifier \(identifier, privacy: .public)")
            try BGTaskScheduler.shared.submit(request)
            Logger.dataBrokerProtection.log("Continued processing: submitted task request for identifier \(identifier, privacy: .public)")
        } catch {
            Logger.dataBrokerProtection.error(
                "Continued processing: failed to submit task request for identifier \(identifier, privacy: .public), error: \(error.localizedDescription, privacy: .public)"
            )
            throw DBPContinuedProcessingError.taskRequestSubmissionFailed(underlyingError: error)
        }
        #endif
    }
}

@available(iOS 26.0, *)
extension DBPContinuedProcessingCoordinator: DBPContinuedProcessingCoordinating {
    /// Applies manager-emitted scan and opt-out events to the current continued-processing run.
    func didEmit(event: DBPContinuedProcessingEvent) {
        guard phase != nil else { return }

        switch event {
        case .scanJobCompleted(let id):
            guard phase == .initialScan else { return }
            progressReporter.recordCompletedScan(id)
            refreshContinuedProcessingUI()
        case .optOutJobCompleted(let id):
            guard phase == .initialOptOut else { return }
            progressReporter.recordCompletedOptOut(id)
            refreshContinuedProcessingUI()
        case .scanPhaseCompleted:
            Task { await handleScanPhaseCompleted() }
        case .optOutPhaseCompleted:
            handleOptOutPhaseCompleted()
        }
    }
}
