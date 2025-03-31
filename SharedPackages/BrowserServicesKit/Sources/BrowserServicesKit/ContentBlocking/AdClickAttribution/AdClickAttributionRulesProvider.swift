//
//  AdClickAttributionRulesProvider.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import TrackerRadarKit
import Common
import os.log

public protocol AdClickAttributionRulesProviding {

    var globalAttributionRules: ContentBlockerRulesManager.Rules? { get }
    func requestAttribution(forVendor vendor: String,
                            completion: @escaping (ContentBlockerRulesManager.Rules?) -> Void)
}

public class AdClickAttributionRulesProvider: AdClickAttributionRulesProviding {

    public enum Constants {
        public static let attributedTempRuleListName = "TemporaryAttributed"
    }

    struct AttributionTask: Equatable {

        let sourceRulesIdentifier: String
        let vendor: String
        let completion: (ContentBlockerRulesManager.Rules?) -> Void

        static func == (lhs: AdClickAttributionRulesProvider.AttributionTask,
                        rhs: AdClickAttributionRulesProvider.AttributionTask) -> Bool {
            return lhs.vendor == rhs.vendor && lhs.sourceRulesIdentifier == rhs.sourceRulesIdentifier
        }
    }

    private let attributionConfig: AdClickAttributing
    private let compiledRulesSource: CompiledRuleListsSource
    private let exceptionsSource: ContentBlockerRulesExceptionsSource
    private let errorReporting: EventMapping<AdClickAttributionDebugEvents>?
    private let compilationErrorReporting: EventMapping<ContentBlockerDebugEvents>?

    private let lock = NSLock()
    private var tasks = [AttributionTask]()
    private var isProcessingTask = false

    private let workQueue = DispatchQueue(label: "AdAttribution compilation queue",
                                          qos: .userInitiated)

    public init(config: AdClickAttributing,
                compiledRulesSource: CompiledRuleListsSource,
                exceptionsSource: ContentBlockerRulesExceptionsSource,
                errorReporting: EventMapping<AdClickAttributionDebugEvents>? = nil,
                compilationErrorReporting: EventMapping<ContentBlockerDebugEvents>? = nil) {
        self.attributionConfig = config
        self.compiledRulesSource = compiledRulesSource
        self.exceptionsSource = exceptionsSource
        self.errorReporting = errorReporting
        self.compilationErrorReporting = compilationErrorReporting
    }

    public var globalAttributionRules: ContentBlockerRulesManager.Rules? {
        return compiledRulesSource.currentAttributionRules
    }

    public func requestAttribution(forVendor vendor: String,
                                   completion: @escaping (ContentBlockerRulesManager.Rules?) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        Logger.contentBlocking.debug("Preparing attribution rules for vendor  \(vendor)")

        guard let globalAttributionRules = compiledRulesSource.currentAttributionRules else {
            errorReporting?.fire(.adAttributionGlobalAttributedRulesDoNotExist)
            Logger.contentBlocking.error("Global attribution list does not exist")
            completion(nil)
            return
        }

        let task = AttributionTask(sourceRulesIdentifier: globalAttributionRules.identifier.stringValue,
                                   vendor: vendor,
                                   completion: completion)
        tasks.append(task)

        workQueue.async {
            self.popTaskAndExecute()
        }
    }

    private func popTaskAndExecute() {
        lock.lock()
        defer { lock.unlock() }

        guard !isProcessingTask, !tasks.isEmpty else { return }

        let task = tasks.removeFirst()
        isProcessingTask = true
        prepareRules(for: task)
    }

    private func prepareRules(for task: AttributionTask) {
        guard let sourceRules = compiledRulesSource.currentAttributionRules else {
            isProcessingTask = false
            workQueue.async {
                self.popTaskAndExecute()
            }
            return
        }

        Logger.contentBlocking.debug("Compiling attribution rules for vendor  \(task.vendor)")

        let mutator = AdClickAttributionRulesMutator(trackerData: sourceRules.trackerData,
                                                     config: attributionConfig)
        let attributedRules = mutator.addException(vendorDomain: task.vendor)

        let attributedDataSet = TrackerDataManager.DataSet(tds: attributedRules,
                                                           etag: sourceRules.etag)
        let attributedRulesList = ContentBlockerRulesList(name: Constants.attributedTempRuleListName,
                                                          trackerData: nil,
                                                          fallbackTrackerData: attributedDataSet)

        let sourceManager = ContentBlockerRulesSourceManager(rulesList: attributedRulesList,
                                                             exceptionsSource: exceptionsSource,
                                                             errorReporting: compilationErrorReporting)

        let compilationTask = ContentBlockerRulesManager.CompilationTask(workQueue: workQueue,
                                                                         rulesList: attributedRulesList,
                                                                         sourceManager: sourceManager)

        compilationTask.start(ignoreCache: true) { compilationTask, _ in
            self.onTaskCompleted(attributionTask: task, compilationTask: compilationTask)
        }
    }

    private func onTaskCompleted(attributionTask: AttributionTask,
                                 compilationTask: ContentBlockerRulesManager.CompilationTask) {
        lock.lock()
        defer { lock.unlock() }

        isProcessingTask = false

        // Take all tasks with same parameters (rules & vendor) and report completion
        // This is optimization: in case multiple tabs request same attribution at the same time, we will respond quickly.
        var matchingTasks = tasks.filter { $0 == attributionTask }
        tasks.removeAll(where: { $0 == attributionTask })

        // Preserve order in which rules were requested
        matchingTasks.insert(attributionTask, at: 0)

        Logger.contentBlocking.debug("Returning attribution rules for vendor  \(attributionTask.vendor) to \(matchingTasks.count, privacy: .public) caller(s)")

        var rules: ContentBlockerRulesManager.Rules?
        if let result = compilationTask.result {
            rules = .init(compilationResult: result)
        }

        DispatchQueue.main.async {
            for task in matchingTasks {
                task.completion(rules)
            }
        }

        if rules == nil {
            errorReporting?.fire(.adAttributionCompilationFailedForAttributedRulesList)
        }

        workQueue.async {
            self.popTaskAndExecute()
        }
    }
}
