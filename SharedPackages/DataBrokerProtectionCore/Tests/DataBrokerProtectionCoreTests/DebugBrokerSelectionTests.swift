//
//  DebugBrokerSelectionTests.swift
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

#if DEBUG
import DataBrokerProtectionCoreTestsUtils
import Foundation
import Testing
@testable import DataBrokerProtectionCore

struct DebugBrokerSelectionTests {
    private let key = "dbp.debug.testBrokerURLs"

    private func defaults() throws -> UserDefaults {
        let suite = "DebugBrokerSelectionTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    private func broker(id: Int64, url: String, removed: Bool = false) -> DataBroker {
        DataBroker(id: id, name: url, url: url, steps: [Step(type: .scan, actions: []), Step(type: .optOut, actions: [])],
                   version: "1.0", schedulingConfig: .mock, optOutUrl: "", eTag: "", removedAt: removed ? Date() : nil)
    }

    private func scan(brokerId: Int64) -> ScanJobData {
        ScanJobData(brokerId: brokerId, profileQueryId: 1, historyEvents: [])
    }

    private func environment(brokers: String?) -> [String: String] {
        var environment = [
            "PIR_SCHEDULER_MODE": "seed",
            "PIR_SCHEDULER_INSTANCE_ID": "123e4567-e89b-42d3-a456-426614174000",
            "PIR_SCHEDULER_RECEIPT": FileManager.default.temporaryDirectory
                .appendingPathComponent("scheduler-launch-\(UUID().uuidString).json").path,
        ]
        environment["PIR_SCHEDULER_BROKERS"] = brokers
        return environment
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [JobType.manualScan, .scheduledScan, .optOut, .all])
    func brokerSelectionRestrictsEveryRegularJobType(jobType: JobType) throws {
        let defaults = try defaults()
        let dependencies = MockBrokerProfileJobDependencies()
        let database = MockDatabase()
        dependencies.database = database
        dependencies.dataBrokerProtectionSettings = DataBrokerProtectionSettings(defaults: defaults)
        let allowed = BrokerProfileQueryData(dataBroker: broker(id: 2, url: "allowed.com"), profileQuery: .mock, scanJobData: scan(brokerId: 2))
        let excluded = BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: .mock)
        let provider = BrokerProfileJobProvider()
        let delegate = MockBrokerProfileJobStatusReportingDelegate()
        func jobs() throws -> [BrokerProfileJob] {
            try provider.createJobs(with: jobType, withPriorityDate: nil, showWebView: false, statusReportingDelegate: delegate,
                                    isAuthenticatedUser: true, jobDependencies: dependencies)
        }
        database.brokerProfileQueryDataToReturn = [allowed, excluded]
        defaults.set(["allowed.com"], forKey: key)
        #expect(try jobs().count == 1)
        defaults.removeObject(forKey: key)
        #expect(try jobs().count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func seedReadsItsBrokersAndStoresOrClearsThemForTheScheduler() throws {
        let defaults = try defaults()
        let settings = DataBrokerProtectionSettings(defaults: defaults)
        let subset = try #require(try PIRDebugLaunchOptions.managedSeed(environment: environment(brokers: #"["a.com","b.com"]"#)))
        #expect(subset.brokerURLs == ["a.com", "b.com"])
        subset.applyBrokerSelection(to: settings)
        #expect(defaults.stringArray(forKey: key) == ["a.com", "b.com"])
        let everyBroker = try #require(try PIRDebugLaunchOptions.managedSeed(environment: environment(brokers: nil)))
        #expect(everyBroker.brokerURLs == nil)
        everyBroker.applyBrokerSelection(to: settings)
        #expect(defaults.stringArray(forKey: key) == nil)
        for invalid in ["[]", "a.com", #"[""]"#, "[1]"] {
            #expect(throws: PIRDebugLaunchOptions.ParseError.invalidManagedRequest) {
                try PIRDebugLaunchOptions.managedSeed(environment: environment(brokers: invalid))
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func seedPlanKeepsOnlyItsBrokersAndRejectsOneWithoutAScan() throws {
        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = [
            BrokerProfileQueryData(dataBroker: broker(id: 1, url: "a.com"), profileQuery: .mock, scanJobData: scan(brokerId: 1)),
            BrokerProfileQueryData(dataBroker: broker(id: 2, url: "b.com"), profileQuery: .mock, scanJobData: scan(brokerId: 2)),
        ]
        let receipt = FileManager.default.temporaryDirectory.appendingPathComponent("unused.json")
        let everyBroker = PIRDebugLaunchOptions.ManagedSeed(mode: .seed, instanceID: "id", receiptURL: receipt)
        let allJobs = try everyBroker.scanJobs(database: database)
        #expect(Set(allJobs.map(\.brokerURL)) == ["a.com", "b.com"])
        let subset = PIRDebugLaunchOptions.ManagedSeed(mode: .seed, instanceID: "id", receiptURL: receipt, brokerURLs: ["b.com"])
        #expect(try subset.scanJobs(database: database).map(\.brokerURL) == ["b.com"])
        let unknown = PIRDebugLaunchOptions.ManagedSeed(mode: .seed, instanceID: "id", receiptURL: receipt, brokerURLs: ["b.com", "c.com"])
        #expect(throws: PIRDebugLaunchOptions.ParseError.unknownBroker(["c.com": "notStored"])) { try unknown.scanJobs(database: database) }
        database.dataBrokersToReturn = [broker(id: 3, url: "c.com", removed: true)]
        #expect(throws: PIRDebugLaunchOptions.ParseError.unknownBroker(["c.com": "removed"])) { try unknown.scanJobs(database: database) }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func immediateScansAreMadeDueBeforeTheyRun() throws {
        let database = MockDatabase()
        database.dataBrokersToReturn = [broker(id: 2, url: "b.com")]
        let before = Date()
        try PIRDebugLaunchOptions.makeScansDue([.init(brokerURL: "b.com", profileQueryId: 5)], database: database)
        #expect(database.wasUpdatedPreferredRunDateForScanCalled)
        #expect(database.lastProfileQueryIdOnScanUpdatePreferredRunDate == 5)
        let due = try #require(database.lastPreferredRunDateOnScan)
        #expect(due >= before && due <= Date())
    }
}
#endif
