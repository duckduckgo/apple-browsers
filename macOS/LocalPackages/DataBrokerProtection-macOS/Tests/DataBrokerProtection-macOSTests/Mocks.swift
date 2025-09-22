//
//  Mocks.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Common
import Configuration
import Foundation
import GRDB
import SecureStorage
import Freemium
import DataBrokerProtectionCore

@testable import DataBrokerProtection_macOS

public class MockDataBrokerProtectionMacOSPixelsHandler: EventMapping<DataBrokerProtectionMacOSPixels> {

    static var lastPixelsFired = [DataBrokerProtectionMacOSPixels]()

    public init() {
        super.init { event, _, _, _ in
            MockDataBrokerProtectionMacOSPixelsHandler.lastPixelsFired.append(event)
        }
    }

    override init(mapping: @escaping EventMapping<DataBrokerProtectionMacOSPixels>.Mapping) {
        fatalError("Use init()")
    }

    func clear() {
        MockDataBrokerProtectionMacOSPixelsHandler.lastPixelsFired.removeAll()
    }
}

final class MockPixelHandler: EventMapping<DataBrokerProtectionMacOSPixels> {

    var lastFiredEvent: DataBrokerProtectionMacOSPixels?
    var lastPassedParameters: [String: String]?

    init() {
        var mockMapping: Mapping! = nil

        super.init(mapping: { event, error, params, onComplete in
            // Call the closure after initialization
            mockMapping(event, error, params, onComplete)
        })

        // Now, set the real closure that captures self and stores parameters.
        mockMapping = { [weak self] (event, error, params, onComplete) in
            // Capture the inputs when fire is called
            self?.lastFiredEvent = event
            self?.lastPassedParameters = params
        }
    }

    func resetCapturedData() {
        lastFiredEvent = nil
        lastPassedParameters = nil
    }
}

final class MockUserNotificationService: DataBrokerProtectionUserNotificationService {

    var requestPermissionWasAsked = false
    var firstScanNotificationWasSent = false
    var firstRemovedNotificationWasSent = false
    var checkInNotificationWasScheduled = false
    var allInfoRemovedWasSent = false

    func requestNotificationPermission() {
        requestPermissionWasAsked = true
    }

    func sendFirstScanCompletedNotification() {
        firstScanNotificationWasSent = true
    }

    func sendFirstRemovedNotificationIfPossible() {
        firstRemovedNotificationWasSent = true
    }

    func sendAllInfoRemovedNotificationIfPossible() {
        allInfoRemovedWasSent = true
    }

    func scheduleCheckInNotificationIfPossible() {
        checkInNotificationWasScheduled = true
    }

    func reset() {
        requestPermissionWasAsked = false
        firstScanNotificationWasSent = false
        firstRemovedNotificationWasSent = false
        checkInNotificationWasScheduled = false
        allInfoRemovedWasSent = false
    }
}

final class MockDataBrokerProtectionBackgroundActivityScheduler: DataBrokerProtectionBackgroundActivityScheduler {
    var dataSource: (any DataBrokerProtection_macOS.DataBrokerProtectionBackgroundActivitySchedulerDataSource)?
    var delegate: DataBrokerProtectionBackgroundActivitySchedulerDelegate?
    var lastTriggerTimestamp: Date?

    var startSchedulerCompletion: (() -> Void)?

    func startScheduler() {
        startSchedulerCompletion?()
    }

    func triggerDelegateCall() async {
        await delegate?.dataBrokerProtectionBackgroundActivitySchedulerDidTrigger(self)
    }
}

final class MockDataBrokerProtectionDataManager: DataBrokerProtectionDataManaging {

    var profileToReturn: DataBrokerProtectionProfile?
    var shouldReturnHasMatches = false

    var communicator: DBPUICommunicator
    var delegate: DataBrokerProtectionDataManagerDelegate?

    init(database: DataBrokerProtectionRepository,
         profileSavedNotifier: DBPProfileSavedNotifier? = nil) {
        communicator = DBPUICommunicator()
    }

    func saveProfile(_ profile: DataBrokerProtectionProfile) async throws {
    }

    func fetchProfile() throws -> DataBrokerProtectionProfile? {
        return profileToReturn
    }

    func prepareProfileCache() throws {
    }

    func fetchBrokerProfileQueryData(ignoresCache: Bool) throws -> [BrokerProfileQueryData] {
        return []
    }

    func prepareBrokerProfileQueryDataCache() throws {
    }

    func hasMatches() throws -> Bool {
        return shouldReturnHasMatches
    }

    func matchesFoundAndBrokersCount() throws -> (matchCount: Int, brokerCount: Int) {
        (0, 0)
    }

    func profileQueriesCount() throws -> Int {
        return 0
    }
}

final class MockIPCServer: DataBrokerProtectionIPCServer {
    var serverDelegate: DataBrokerProtectionAppToAgentInterface?

    init(machServiceName: String) {
    }

    func activate() {
    }

    func register() {
    }

    func profileSaved(xpcMessageReceivedCompletion: @escaping (Error?) -> Void) {
        Task {
            await serverDelegate?.profileSaved()
        }
    }

    func appLaunched(xpcMessageReceivedCompletion: @escaping (Error?) -> Void) {
        Task {
            await serverDelegate?.appLaunched()
        }
    }

    func openBrowser(domain: String) {
        serverDelegate?.openBrowser(domain: domain)
    }

    func startImmediateOperations(showWebView: Bool) {
        serverDelegate?.startImmediateOperations(showWebView: showWebView)
    }

    func startScheduledOperations(showWebView: Bool) {
        serverDelegate?.startScheduledOperations(showWebView: showWebView)
    }

    func runAllOptOuts(showWebView: Bool) {
        serverDelegate?.runAllOptOuts(showWebView: showWebView)
    }

    func getDebugMetadata(completion: @escaping (DBPBackgroundAgentMetadata?) -> Void) {
        Task {
            await serverDelegate?.profileSaved()
        }
    }

    func checkForEmailConfirmationData() {
        Task {
            await serverDelegate?.checkForEmailConfirmationData()
        }
    }

    func runEmailConfirmationOperations(showWebView: Bool) {
        Task {
            await serverDelegate?.runEmailConfirmationOperations(showWebView: showWebView)
        }
    }
}

final class MockAgentStopper: DataBrokerProtectionAgentStopper {
    var validateRunPrerequisitesCompletion: (() -> Void)?
    var monitorEntitlementCompletion: (() -> Void)?

    func validateRunPrerequisitesAndStopAgentIfNecessary() async {
        validateRunPrerequisitesCompletion?()
    }

    func monitorEntitlementAndStopAgentIfEntitlementIsInvalidAndUserIsNotFreemium(interval: TimeInterval) {
        monitorEntitlementCompletion?()
    }
}

final class MockDataProtectionStopAction: DataProtectionStopAction {
    var wasStopCalled = false
    var stopAgentCompletion: (() -> Void)?

    func stopAgent() {
        wasStopCalled = true
        stopAgentCompletion?()
    }

    func reset() {
        wasStopCalled = false
    }
}

struct MockGroupNameProvider: GroupNameProviding {
    var appGroupName: String {
        return "mockGroup"
    }
}

final class MockDBPProfileSavedNotifier: DBPProfileSavedNotifier {

    var didCallPostProfileSavedNotificationIfPermitted = false

    func postProfileSavedNotificationIfPermitted() {
        didCallPostProfileSavedNotificationIfPermitted = true
    }
}

public final class MockFreemiumDBPUserStateManager: FreemiumDBPUserStateManager {
    public var didActivate = false
    public var didPostFirstProfileSavedNotification = false
    public var didPostResultsNotification = false
    public var didDismissHomePagePromotion = false
    public var firstProfileSavedTimestamp: Date?
    public var upgradeToSubscriptionTimestamp: Date?
    public var firstScanResults: FreemiumDBPMatchResults?

    public init() {}

    public func resetAllState() {}
}
