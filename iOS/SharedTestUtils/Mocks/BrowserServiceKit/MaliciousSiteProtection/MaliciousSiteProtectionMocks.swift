//
//  MaliciousSiteProtectionMocks.swift
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

import BackgroundTasks
import Combine
import enum UIKit.UIBackgroundRefreshStatus
import Foundation
import MaliciousSiteProtection
@testable import DuckDuckGo

final class MockMaliciousSiteProtectionUpdateManager: MaliciousSiteUpdateManaging {
    private(set) var updateDatasets: [MaliciousSiteProtection.DataManager.StoredDataType.Kind: Bool] = [
        .hashPrefixSet: false,
        .filterSet: false
    ]
    private(set) var updateCallCount = 0

    var lastHashPrefixSetUpdateDate: Date = .distantPast
    var lastFilterSetUpdateDate: Date = .distantPast

    var nextUpdateTask: Task<Void, Never>?

    func startPeriodicUpdates() -> Task<Void, any Error> {
        Task { }
    }
    
    func updateData(datasetType: MaliciousSiteProtection.DataManager.StoredDataType.Kind) -> Task<Void, Never> {
        updateCallCount += 1
        updateDatasets[datasetType] = true
        let task = nextUpdateTask ?? Task {}
        nextUpdateTask = nil
        return task
    }
}

final class MockMaliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging {
    var isMaliciousSiteProtectionOn: Bool = false {
        didSet {
            subject.send(isMaliciousSiteProtectionOn)
        }
    }

    private lazy var subject = CurrentValueSubject<Bool, Never>(isMaliciousSiteProtectionOn)

    var isMaliciousSiteProtectionOnPublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }
}

final class MockMaliciousSiteProtectionFeatureFlags: MaliciousSiteProtectionFeatureFlagger, MaliciousSiteProtectionFeatureFlagsSettingsProvider {

    var isScamProtectionEnabled = false

    var shouldDetectMaliciousThreatForDomainResult = false

    var isMaliciousSiteProtectionEnabled = false

    var hashPrefixUpdateFrequency: Int = 10

    var filterSetUpdateFrequency: Int = 20

    func shouldDetectMaliciousThreat(forDomain domain: String?) -> Bool {
        shouldDetectMaliciousThreatForDomainResult
    }
}

final class MockBackgroundScheduler: BGTaskScheduling {
    private(set) var capturedRegisteredTaskIdentifiers: [String: Int] = [:]

    private(set) var didCallSubmitTaskRequest = false
    private(set) var capturedSubmittedTaskRequest: BGTaskRequest?
    private(set) var submittedTaskRequests: [BGTaskRequest] = []

    private(set) var canceledTaskRequestIdentifiers: [String] = []

    var launchHandlers: [String: ((BGTaskInterface) -> Void)?] = [:]

    func register(forTaskWithIdentifier identifier: String, launchHandler: @escaping (BGTaskInterface) -> Void) -> Bool {
        var counterForTaskIdentifier = capturedRegisteredTaskIdentifiers[identifier] ?? 0
        counterForTaskIdentifier += 1
        capturedRegisteredTaskIdentifiers[identifier] = counterForTaskIdentifier
        self.launchHandlers[identifier] = launchHandler
        return true
    }
    
    func submit(_ taskRequest: BGTaskRequest) throws {
        didCallSubmitTaskRequest = true
        capturedSubmittedTaskRequest = taskRequest
        submittedTaskRequests.append(taskRequest)
    }
    
    func cancel(taskRequestWithIdentifier identifier: String) {
        canceledTaskRequestIdentifiers.append(identifier)
    }
    
    func pendingTaskRequests() async -> [BGTaskRequest] {
        []
    }

    func getPendingTaskRequests(completionHandler: @escaping ([BGTaskRequest]) -> Void) {
        completionHandler([])
    }
}

final class MockBGTask: BGTaskInterface {
    private(set) var didCallSetTaskCompleted = false
    private(set) var capturedTaskCompletedSuccess: Bool?

    let identifier: String
    var expirationHandler: (() -> Void)?
    var onCompletion: ((Bool) -> Void)?

    init(identifier: String) {
        self.identifier = identifier
    }

    func setTaskCompleted(success: Bool) {
        didCallSetTaskCompleted = true
        capturedTaskCompletedSuccess = success
        onCompletion?(success)
    }
}

final class MockMaliciousSiteProtectionDataFetcher: MaliciousSiteProtectionDatasetsFetching {
    private(set) var didCallStartFetching = false
    private(set) var didCallRegisterBackgroundRefreshTaskHandler = false

    @MainActor
    @discardableResult
    func startFetching() -> Task<Void, Never> {
        didCallStartFetching = true
        return Task {}
    }
    
    func registerBackgroundRefreshTaskHandler() {
        didCallRegisterBackgroundRefreshTaskHandler = true
    }
}

final class MockBackgroundRefreshApplication: BackgroundRefreshCapable {
    var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
}

final class MockMaliciousSiteFileStore: MaliciousSiteProtection.FileStoring {
    private var storage: [String: Data] = [:]
    var didWriteToDisk: Bool = false
    var didReadFromDisk: Bool = false

    func write(data: Data, to filename: String) throws {
        didWriteToDisk = true
        storage[filename] = data
    }

    func read(from filename: String) -> Data? {
        didReadFromDisk = true
        return storage[filename]
    }
}

final class MockMaliciousSiteDetector: MaliciousSiteProtection.MaliciousSiteDetecting {

    var isMalicious: (URL) -> MaliciousSiteProtection.ThreatKind? = { url in
        if url.absoluteString.contains("phishing") {
            .phishing
        } else if url.absoluteString.contains("malware") {
            .malware
        } else if url.absoluteString.contains("scam") {
            .scam
        } else {
            nil
        }
    }

    init(isMalicious: ((URL) -> MaliciousSiteProtection.ThreatKind?)? = nil) {
        if let isMalicious {
            self.isMalicious = isMalicious
        }
    }

    func evaluate(_ url: URL) async -> MaliciousSiteProtection.ThreatKind? {
        return isMalicious(url)
    }

}

final class MockMaliciousSiteProtectionPreferencesStore: MaliciousSiteProtectionPreferencesStorage {
    var isEnabled: Bool = true
}
