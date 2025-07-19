//
//  BrokerProfileJobQueueManager.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Foundation
import os.log

public protocol BrokerProfileJobQueue {
    var maxConcurrentOperationCount: Int { get set }
    func cancelAllOperations()
    func addOperation(_ op: Operation)
    func addBarrierBlock1(_ barrier: @escaping @Sendable () -> Void)
}

extension OperationQueue: BrokerProfileJobQueue {
    public func addBarrierBlock1(_ barrier: @escaping () -> Void) {
        addBarrierBlock(barrier)
    }
}

enum BrokerProfileJobQueueMode {
    case idle
    case immediate(errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?, completion: (() -> Void)?)
    case scheduled(errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?, completion: (() -> Void)?)

    var priorityDate: Date? {
        switch self {
        case .idle, .immediate:
            return nil
        case .scheduled:
            return Date()
        }
    }

    func canBeInterruptedBy(newMode: BrokerProfileJobQueueMode) -> Bool {
        switch (self, newMode) {
        case (.idle, _):
            return true
        case (_, .immediate):
            return true
        default:
            return false
        }
    }
}

public enum BrokerProfileJobQueueError: Error {
    case cannotInterrupt
    case interrupted
}

public enum DataBrokerProtectionQueueManagerDebugCommand {
    case startOptOutOperations(showWebView: Bool,
                               jobDependencies: BrokerProfileJobDependencyProviding,
                               errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                               completion: (() -> Void)?)
}

public protocol BrokerProfileJobQueueManaging {
    var delegate: BrokerProfileJobQueueManagerDelegate? { get set }

    init(jobQueue: BrokerProfileJobQueue,
         jobProvider: BrokerProfileJobProviding,
         mismatchCalculator: MismatchCalculator,
         pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>)

    func startImmediateScanOperationsIfPermitted(showWebView: Bool,
                                                 jobDependencies: BrokerProfileJobDependencyProviding,
                                                 errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                                 completion: (() -> Void)?)
    func startScheduledAllOperationsIfPermitted(showWebView: Bool,
                                                jobDependencies: BrokerProfileJobDependencyProviding,
                                                errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                                completion: (() -> Void)?)
    func startScheduledScanOperationsIfPermitted(showWebView: Bool,
                                                 jobDependencies: BrokerProfileJobDependencyProviding,
                                                 errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                                 completion: (() -> Void)?)
    func stop()

    func execute(_ command: DataBrokerProtectionQueueManagerDebugCommand)
    var debugRunningStatusString: String { get }
}

public protocol BrokerProfileJobQueueManagerDelegate: AnyObject {
    func queueManagerWillEnqueueOperations(_ queueManager: BrokerProfileJobQueueManaging)
}

public final class BrokerProfileJobQueueManager: BrokerProfileJobQueueManaging {
    public weak var delegate: BrokerProfileJobQueueManagerDelegate?

    private var jobQueue: BrokerProfileJobQueue
    private let jobProvider: BrokerProfileJobProviding
    private let mismatchCalculator: MismatchCalculator
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>

    private var mode = BrokerProfileJobQueueMode.idle
    private var operationErrors: [Error] = []

    public var debugRunningStatusString: String {
        switch mode {
        case .idle:
            return "idle"
        case .immediate,
                .scheduled:
            return "running"
        }
    }

    public init(jobQueue: BrokerProfileJobQueue,
                jobProvider: BrokerProfileJobProviding,
                mismatchCalculator: MismatchCalculator,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>) {

        self.jobQueue = jobQueue
        self.jobProvider = jobProvider
        self.mismatchCalculator = mismatchCalculator
        self.pixelHandler = pixelHandler
    }

    public func startImmediateScanOperationsIfPermitted(showWebView: Bool,
                                                        jobDependencies: BrokerProfileJobDependencyProviding,
                                                        errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                                        completion: (() -> Void)?) {

        let newMode = BrokerProfileJobQueueMode.immediate(errorHandler: errorHandler, completion: completion)
        startJobsIfPermitted(forNewMode: newMode,
                             type: .manualScan,
                             showWebView: showWebView,
                             jobDependencies: jobDependencies) { [weak self] errors in
            self?.mismatchCalculator.calculateMismatches()
            errorHandler?(errors)
        } completion: {
            completion?()
        }
    }

    public func startScheduledAllOperationsIfPermitted(showWebView: Bool,
                                                       jobDependencies: BrokerProfileJobDependencyProviding,
                                                       errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                                       completion: (() -> Void)?) {
        startScheduledJobsIfPermitted(for: .all,
                                      showWebView: showWebView,
                                      jobDependencies: jobDependencies,
                                      errorHandler: errorHandler,
                                      completion: completion)
    }

    public func startScheduledScanOperationsIfPermitted(showWebView: Bool,
                                                        jobDependencies: BrokerProfileJobDependencyProviding,
                                                        errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                                        completion: (() -> Void)?) {
        startScheduledJobsIfPermitted(for: .scheduledScan,
                                      showWebView: showWebView,
                                      jobDependencies: jobDependencies,
                                      errorHandler: errorHandler,
                                      completion: completion)
    }

    public func execute(_ command: DataBrokerProtectionQueueManagerDebugCommand) {
        guard case .startOptOutOperations(let showWebView,
                                          let operationDependencies,
                                          let errorHandler,
                                          let completion) = command else { return }

        cancelCurrentModeAndResetIfNeeded()
        mode = .immediate(errorHandler: nil, completion: nil)
        addJobs(for: .optOut,
                      showWebView: showWebView,
                      jobDependencies: operationDependencies,
                      errorHandler: errorHandler,
                      completion: completion)
    }

    public func stop() {
        cancelCurrentModeAndResetIfNeeded()
    }
}

private extension BrokerProfileJobQueueManager {

    func startScheduledJobsIfPermitted(for jobType: JobType,
                                       showWebView: Bool,
                                       jobDependencies: BrokerProfileJobDependencyProviding,
                                       errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                       completion: (() -> Void)?) {
        let newMode = BrokerProfileJobQueueMode.scheduled(errorHandler: errorHandler, completion: completion)
        startJobsIfPermitted(forNewMode: newMode,
                             type: jobType,
                             showWebView: showWebView,
                             jobDependencies: jobDependencies,
                             errorHandler: errorHandler,
                             completion: completion)
    }

    func startJobsIfPermitted(forNewMode newMode: BrokerProfileJobQueueMode,
                              type: JobType,
                              showWebView: Bool,
                              jobDependencies: BrokerProfileJobDependencyProviding,
                              errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                              completion: (() -> Void)?) {

        guard mode.canBeInterruptedBy(newMode: newMode) else {
            let error = BrokerProfileJobQueueError.cannotInterrupt
            let errorCollection = DataBrokerProtectionJobsErrorCollection(oneTimeError: error)
            errorHandler?(errorCollection)
            completion?()
            return
        }

        if delegate != nil {
            jobQueue.addBarrierBlock1 { [weak self] in
                guard let self, let delegate = self.delegate else { return }
                delegate.queueManagerWillEnqueueOperations(self)
            }
        }

        cancelCurrentModeAndResetIfNeeded()
        mode = newMode

        addJobs(for: type,
                priorityDate: mode.priorityDate,
                showWebView: showWebView,
                jobDependencies: jobDependencies,
                errorHandler: errorHandler,
                completion: completion)
    }

    func cancelCurrentModeAndResetIfNeeded() {
        switch mode {
        case .immediate(let errorHandler, let completion), .scheduled(let errorHandler, let completion):
            jobQueue.cancelAllOperations()
            let errorCollection = DataBrokerProtectionJobsErrorCollection(oneTimeError: BrokerProfileJobQueueError.interrupted, operationErrors: operationErrorsForCurrentOperations())
            errorHandler?(errorCollection)
            resetMode(clearErrors: true)
            completion?()
            resetMode()
        default:
            break
        }
    }

    func resetMode(clearErrors: Bool = false) {
        mode = .idle
        if clearErrors {
            operationErrors = []
        }
    }

    func addJobs(for jobType: JobType,
                 priorityDate: Date? = nil,
                 showWebView: Bool,
                 jobDependencies: BrokerProfileJobDependencyProviding,
                 errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                 completion: (() -> Void)?) {

        jobQueue.maxConcurrentOperationCount = jobDependencies.executionConfig.concurrentJobsFor(jobType)

        let jobs: [BrokerProfileJob]
        do {
            jobs = try jobProvider.createJobs(with: jobType,
                                                    withPriorityDate: priorityDate,
                                                    showWebView: showWebView,
                                                    errorDelegate: self,
                                                    jobDependencies: jobDependencies)

            for job in jobs {
                jobQueue.addOperation(job)
            }
        } catch {
            Logger.dataBrokerProtection.error("DataBrokerProtectionProcessor error: addOperations, error: \(error.localizedDescription, privacy: .public)")
            errorHandler?(DataBrokerProtectionJobsErrorCollection(oneTimeError: error))
            completion?()
            return
        }

        jobQueue.addBarrierBlock1 { [weak self] in
            let errorCollection = DataBrokerProtectionJobsErrorCollection(oneTimeError: nil, operationErrors: self?.operationErrorsForCurrentOperations())
            errorHandler?(errorCollection)
            self?.resetMode(clearErrors: true)
            completion?()
            self?.resetMode()
        }
    }

    func operationErrorsForCurrentOperations() -> [Error]? {
        return operationErrors.count != 0 ? operationErrors : nil
    }
}

extension BrokerProfileJobQueueManager: BrokerProfileJobErrorDelegate {
    public func dataBrokerOperationDidError(_ error: any Error, withBrokerName brokerName: String?, version: String?) {
        operationErrors.append(error)

        guard let error = error as? DataBrokerProtectionError, let brokerName, let version else { return }

        switch error {
        case .httpError(let code):
            pixelHandler.fire(.httpError(error: error, code: code, dataBroker: brokerName, version: version))
        case .actionFailed(let actionId, let message):
            pixelHandler.fire(.actionFailedError(error: error, actionId: actionId, message: message, dataBroker: brokerName, version: version))
        default:
            pixelHandler.fire(.otherError(error: error, dataBroker: brokerName, version: version))
        }
    }
}
