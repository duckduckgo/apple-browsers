//
//  DBPUICommunicationLayerTests.swift
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

import XCTest
import Testing
import AppKit
import WebKit
@testable import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import BrowserServicesKitTestsUtils
import PrivacyConfig

final class DBPUICommunicationLayerTests: XCTestCase {

    @MainActor
    func testWhenTwoViewsChangeToSameEntryPoint_thenBothReloadAndUseTheirOwnHandshake() async throws {
        let dataManager = DataBrokerProtectionDataManager(database: MockDatabase())
        let modelA = makeViewModel(dataManager: dataManager)
        let modelB = makeViewModel(dataManager: dataManager)
        let webViewA = ReloadRecordingWebView()
        let webViewB = ReloadRecordingWebView()
        let layerA = try communicationLayer(for: modelA)
        let layerB = try communicationLayer(for: modelB)

        modelA.setFreeScanEntryPoint("banner", in: nil)
        modelB.setFreeScanEntryPoint("banner", in: nil)
        let initialA = try await handshake(layerA)
        let initialB = try await handshake(layerB)
        XCTAssertEqual(initialA.userdata.freeScanEntryPoint, "banner")
        XCTAssertEqual(initialB.userdata.freeScanEntryPoint, "banner")

        modelA.setFreeScanEntryPoint("app_menu", in: webViewA)
        let updatedA = try await handshake(layerA)
        modelB.setFreeScanEntryPoint("app_menu", in: webViewB)
        let updatedB = try await handshake(layerB)

        XCTAssertEqual(webViewA.reloadCount, 1)
        XCTAssertEqual(webViewB.reloadCount, 1)
        XCTAssertEqual(updatedA.userdata.freeScanEntryPoint, "app_menu")
        XCTAssertEqual(updatedB.userdata.freeScanEntryPoint, "app_menu")

        modelB.setFreeScanEntryPoint("app_menu", in: webViewB)
        XCTAssertEqual(webViewB.reloadCount, 1)
    }

    @MainActor
    func testWhenOtherViewChangesEntryPoint_thenLaterHandshakeRetainsThisViewsEntryPoint() async throws {
        let dataManager = DataBrokerProtectionDataManager(database: MockDatabase())
        let modelA = makeViewModel(dataManager: dataManager)
        let modelB = makeViewModel(dataManager: dataManager)
        let webViewA = ReloadRecordingWebView()
        let webViewB = ReloadRecordingWebView()
        let layerA = try communicationLayer(for: modelA)
        let layerB = try communicationLayer(for: modelB)

        modelA.setFreeScanEntryPoint("banner", in: nil)
        modelB.setFreeScanEntryPoint("app_menu", in: nil)
        _ = try await handshake(layerA)
        _ = try await handshake(layerB)

        modelB.setFreeScanEntryPoint("view_results", in: webViewB)
        let updatedB = try await handshake(layerB)
        let reloadedA = try await handshake(layerA)
        modelA.setFreeScanEntryPoint("banner", in: webViewA)

        XCTAssertEqual(updatedB.userdata.freeScanEntryPoint, "view_results")
        XCTAssertEqual(reloadedA.userdata.freeScanEntryPoint, "banner")
        XCTAssertEqual(webViewA.reloadCount, 0)
        XCTAssertEqual(webViewB.reloadCount, 1)
    }

    func testWhenHandshakeCalled_andDelegateAuthenticatedUserTrue_thenHandshakeUserDataTrue() async throws {
        // Given
        let mockDelegate = MockDelegate()
        let handshakeUserData = DBPUIHandshakeUserData(isAuthenticatedUser: true, isUserEligibleForFreeTrial: false)
        mockDelegate.handshakeUserDataToReturn = handshakeUserData
        var sut = makeSUT(handshakeDelegate: mockDelegate)
        sut.delegate = mockDelegate
        let handshakeParams: [String: Any] = ["version": 4]
        let scriptMessage = WKScriptMessage.mock()

        // When
        let handler = sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)
        let result = try await handler?(handshakeParams, scriptMessage)

        // Then
        XCTAssertTrue(mockDelegate.handshakeUserDataCalled)

        guard let resultUserData = result as? DBPUIHandshakeResponse else {
            XCTFail("Expected DBPUIHandshakeResponse to be returned")
            return
        }

        XCTAssertEqual(resultUserData.userdata.isAuthenticatedUser, true)
    }

    func testWhenHandshakeCalled_andDelegateAuthenticatedUserFalse_thenHandshakeUserDataFalse() async throws {
        // Given
        let mockDelegate = MockDelegate()
        let handshakeUserData = DBPUIHandshakeUserData(isAuthenticatedUser: false, isUserEligibleForFreeTrial: false)
        mockDelegate.handshakeUserDataToReturn = handshakeUserData
        var sut = makeSUT(handshakeDelegate: mockDelegate)
        sut.delegate = mockDelegate
        let handshakeParams: [String: Any] = ["version": 4]
        let scriptMessage = WKScriptMessage.mock()

        // When
        let handler = sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)
        let result = try await handler?(handshakeParams, scriptMessage)

        // Then
        XCTAssertTrue(mockDelegate.handshakeUserDataCalled)

        guard let resultUserData = result as? DBPUIHandshakeResponse else {
            XCTFail("Expected DBPUIHandshakeResponse to be returned")
            return
        }

        XCTAssertEqual(resultUserData.userdata.isAuthenticatedUser, false)
    }

    func testWhenHandshakeCalled_andDelegateUserElgibleFreeTrialTrue_thenHandshakeUserDataTrue() async throws {
        // Given
        let mockDelegate = MockDelegate()
        let handshakeUserData = DBPUIHandshakeUserData(isAuthenticatedUser: true, isUserEligibleForFreeTrial: true)
        mockDelegate.handshakeUserDataToReturn = handshakeUserData
        var sut = makeSUT(handshakeDelegate: mockDelegate)
        sut.delegate = mockDelegate
        let handshakeParams: [String: Any] = ["version": 4]
        let scriptMessage = WKScriptMessage.mock()

        // When
        let handler = sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)
        let result = try await handler?(handshakeParams, scriptMessage)

        // Then
        XCTAssertTrue(mockDelegate.handshakeUserDataCalled)

        guard let resultUserData = result as? DBPUIHandshakeResponse else {
            XCTFail("Expected DBPUIHandshakeResponse to be returned")
            return
        }

        XCTAssertEqual(resultUserData.userdata.isUserEligibleForFreeTrial, true)
    }

    func testWhenHandshakeCalled_andDelegateUserElgibleFreeTrialFalse_thenHandshakeUserDataFalse() async throws {
        // Given
        let mockDelegate = MockDelegate()
        let handshakeUserData = DBPUIHandshakeUserData(isAuthenticatedUser: false, isUserEligibleForFreeTrial: false)
        mockDelegate.handshakeUserDataToReturn = handshakeUserData
        var sut = makeSUT(handshakeDelegate: mockDelegate)
        sut.delegate = mockDelegate
        let handshakeParams: [String: Any] = ["version": 4]
        let scriptMessage = WKScriptMessage.mock()

        // When
        let handler = sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)
        let result = try await handler?(handshakeParams, scriptMessage)

        // Then
        XCTAssertTrue(mockDelegate.handshakeUserDataCalled)

        guard let resultUserData = result as? DBPUIHandshakeResponse else {
            XCTFail("Expected DBPUIHandshakeResponse to be returned")
            return
        }

        XCTAssertEqual(resultUserData.userdata.isUserEligibleForFreeTrial, false)
    }

    func testWhenHandshakeCalled_andHandshakeDelegateReturnsNil_thenHandshakeUserDataIsDefaultTrue() async throws {
        // Given
        let mockDelegate = MockDelegate()
        let sut = makeSUT(handshakeDelegate: mockDelegate)
        let handshakeParams: [String: Any] = ["version": 4]
        let scriptMessage = WKScriptMessage.mock()

        // When
        let handler = sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)
        let result = try await handler?(handshakeParams, scriptMessage)

        // Then
        guard let resultUserData = result as? DBPUIHandshakeResponse else {
            XCTFail("Expected DBPUIHandshakeResponse to be returned")
            return
        }

        XCTAssertEqual(resultUserData.userdata.isAuthenticatedUser, true)
        XCTAssertEqual(resultUserData.userdata.isUserEligibleForFreeTrial, false)
    }

    func testWhenGetFeatureConfigCalled_thenReturnsProperObjectStructure() async throws {
        // Given
        let mockPrivacyConfig = PrivacyConfigurationManagingMock()
        let mockVPNBypassService = VPNBypassServiceProviderMock()

        (mockPrivacyConfig.privacyConfig as! PrivacyConfigurationMock).isSubfeatureEnabledCheck = { subfeature in
            if let proSubfeature = subfeature as? PrivacyProSubfeature {
                return proSubfeature == .useUnifiedFeedback
            }
            return false
        }
        mockVPNBypassService.isSupported = true

        let mockDelegate = MockDelegate()
        let sut = makeSUT(privacyConfig: mockPrivacyConfig, vpnBypassService: mockVPNBypassService, handshakeDelegate: mockDelegate)
        let scriptMessage = WKScriptMessage.mock()

        // When
        let handler = sut.handler(forMethodNamed: DBPUIReceivedMethodName.getFeatureConfig.rawValue)
        let result = try await handler?([:], scriptMessage)

        // Then
        guard let featureConfig = result as? DBPUIFeatureConfigurationResponse else {
            XCTFail("Expected DBPUIFeatureConfigurationResponse to be returned, got \(type(of: result))")
            return
        }

        XCTAssertEqual(featureConfig.useUnifiedFeedback, true)
        XCTAssertEqual(featureConfig.excludeVpnTraffic, true)
    }

    @MainActor
    private func makeViewModel(dataManager: DataBrokerProtectionDataManaging) -> DBPUIViewModel {
        DBPUIViewModel(dataManager: dataManager,
                       agentInterface: HandshakeAgentInterface(),
                       webUISettings: MockWebSettings(),
                       pixelHandler: MockDataBrokerProtectionPixelsHandler(),
                       privacyConfig: PrivacyConfigurationManagingMock(),
                       prefs: .mock,
                       dbpSettings: DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: "DBPUICommunicationLayerTests.\(UUID().uuidString)")!))
    }

    @MainActor
    private func communicationLayer(for model: DBPUIViewModel) throws -> DBPUICommunicationLayer {
        let configuration = try XCTUnwrap(model.setupCommunicationLayer())
        let controller = try XCTUnwrap(configuration.userContentController as? DBPUIUserContentController)
        return controller.dbpUIUserScripts.dbpUICommunicationLayer
    }

    private func handshake(_ layer: DBPUICommunicationLayer) async throws -> DBPUIHandshakeResponse {
        let handler = try XCTUnwrap(layer.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue))
        let result = try await handler(["version": 12], WKScriptMessage.mock())
        return try XCTUnwrap(result as? DBPUIHandshakeResponse)
    }

    func testWhenSigningKeyIsRevoked_thenScanDataIsNotServedAndScansDoNotStart() async throws {
        let privacyConfig = PrivacyConfigurationManagingMock()
        privacyConfig.setRevokedBundleSigningKeyIDs(PrivacyConfigurationManagingMock.builtInBundleSigningKeyIDs)
        let mockDelegate = MockDelegate()
        mockDelegate.startScanAndOptOutResult = true
        var sut = makeSUT(privacyConfig: privacyConfig)
        sut.delegate = mockDelegate

        for method in [DBPUIReceivedMethodName.initialScanStatus, .maintenanceScanStatus, .startScanAndOptOut] {
            let result = try await sut.handler(forMethodNamed: method.rawValue)?([:], WKScriptMessage.mock())
            let response = try XCTUnwrap(result as? DBPUIStandardResponse, "\(method)")
            XCTAssertFalse(response.success, "\(method)")
            XCTAssertEqual(response.id, "UPDATE_REQUIRED", "\(method)")
        }
        let brokers = try await sut.handler(forMethodNamed: DBPUIReceivedMethodName.getDataBrokers.rawValue)?([:], WKScriptMessage.mock())
        XCTAssertEqual(try XCTUnwrap(brokers as? DBPUIDataBrokerList).dataBrokers.count, 0)

        XCTAssertFalse(mockDelegate.getInitialScanStateCalled)
        XCTAssertFalse(mockDelegate.getMaintenanceScanStateCalled)
        XCTAssertFalse(mockDelegate.getDataBrokersCalled)
        XCTAssertFalse(mockDelegate.startScanAndOptOutCalled)
    }

    func testWhenSigningKeyIsRevoked_thenHandshakeStatusIsUpdateRequired() async throws {
        let privacyConfig = PrivacyConfigurationManagingMock()
        privacyConfig.setRevokedBundleSigningKeyIDs(PrivacyConfigurationManagingMock.builtInBundleSigningKeyIDs)
        let sut = makeSUT(privacyConfig: privacyConfig)

        let pausedResult = try await sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)?(["version": 12], WKScriptMessage.mock())
        let pausedResponse = try XCTUnwrap(pausedResult as? DBPUIHandshakeResponse)
        XCTAssertTrue(pausedResponse.success)
        XCTAssertEqual(pausedResponse.status, .updateRequired)
        XCTAssertTrue(try XCTUnwrap(String(data: JSONEncoder().encode(pausedResponse), encoding: .utf8)).contains("\"status\":\"updateRequired\""))
    }

    // MARK: - Helpers

    private func makeSUT(privacyConfig: PrivacyConfigurationManagingMock = PrivacyConfigurationManagingMock(),
                         vpnBypassService: VPNBypassServiceProvider? = nil,
                         handshakeDelegate: DBPUIHandshakeDelegate = MockDelegate()) -> DBPUICommunicationLayer {
        let settings = DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: "DBPUICommunicationLayerTests.\(UUID().uuidString)")!)
        return DBPUICommunicationLayer(webURLSettings: MockWebSettings(),
                                       handshakeDelegate: handshakeDelegate,
                                       vpnBypassService: vpnBypassService,
                                       privacyConfig: privacyConfig,
                                       keyRevocationChecker: BrokerBundleKeyRevocationChecker(privacyConfigurationManager: privacyConfig,
                                                                                              settings: settings))
    }
}

// MARK: - Mock Classes

private final class ReloadRecordingWebView: WKWebView {
    private(set) var reloadCount = 0
    override var url: URL? { URL(string: "https://duckduckgo.com") }

    override func reload() -> WKNavigation? {
        reloadCount += 1
        return nil
    }
}

private final class HandshakeAgentInterface: DataBrokerProtectionAppToAgentInterface {
    func assistedOptOutDataDidChange() {}
    func getAssistedOptOuts() async -> AssistedOptOutList? { AssistedOptOutList(optOuts: []) }
    func startAssistedOptOut(id: String) {}
    func profileSaved() async {}
    func appLaunched() async {}
    func openBrowser(domain: String) {}
    func startImmediateOperations(showWebView: Bool) {}
    func startScheduledOperations(showWebView: Bool) {}
    func runAllOptOuts(showWebView: Bool) {}
    func checkForEmailConfirmationData() async {}
    func runEmailConfirmationOperations(showWebView: Bool) async {}
    func getDebugMetadata() async -> DBPBackgroundAgentMetadata? { nil }
    func startDebugServer() async -> Bool { false }
    func stopDebugServer() {}
}

private final class MockDelegate: DBPUICommunicationDelegate, DBPUIHandshakeDelegate {
    var handshakeUserDataCalled = false
    var handshakeUserDataToReturn: DBPUIHandshakeUserData?

    func getHandshakeUserData() async -> DBPUIHandshakeUserData? {
        handshakeUserDataCalled = true
        return handshakeUserDataToReturn
    }

    func saveProfile() async throws {}
    func getUserProfile() -> DBPUIUserProfile? { nil }
    func deleteProfileData() throws {}
    func addNameToCurrentUserProfile(_ name: DBPUIUserProfileName) -> Bool { false }
    func setNameAtIndexInCurrentUserProfile(_ payload: DBPUINameAtIndex) -> Bool { false }
    func removeNameAtIndexFromUserProfile(_ index: DBPUIIndex) -> Bool { false }
    func setBirthYearForCurrentUserProfile(_ year: DBPUIBirthYear) -> Bool { false }
    func addAddressToCurrentUserProfile(_ address: DBPUIUserProfileAddress) -> Bool { false }
    func setAddressAtIndexInCurrentUserProfile(_ payload: DBPUIAddressAtIndex) -> Bool { false }
    func removeAddressAtIndexFromUserProfile(_ index: DBPUIIndex) -> Bool { false }
    var startScanAndOptOutResult = false
    var startScanAndOptOutCalled = false
    var getInitialScanStateCalled = false
    var getMaintenanceScanStateCalled = false
    var getDataBrokersCalled = false

    func startScanAndOptOut() -> Bool {
        startScanAndOptOutCalled = true
        return startScanAndOptOutResult
    }

    func getInitialScanState() async -> DBPUIInitialScanState {
        getInitialScanStateCalled = true
        return DBPUIInitialScanState(resultsFound: [], scanProgress: .init(currentScans: 0, totalScans: 0, scannedBrokers: []))
    }

    func getMaintenanceScanState() async -> DBPUIScanAndOptOutMaintenanceState {
        getMaintenanceScanStateCalled = true
        return DBPUIScanAndOptOutMaintenanceState(
            inProgressOptOuts: [],
            completedOptOuts: [],
            scanSchedule: .init(lastScan: .init(date: 2, dataBrokers: []), nextScan: .init(date: 2, dataBrokers: [])),
            scanHistory: .init(sitesScanned: 2)
        )
    }

    func getDataBrokers() async -> [DBPUIDataBroker] {
        getDataBrokersCalled = true
        return []
    }

    func getBackgroundAgentMetadata() async -> DBPUIDebugMetadata {
        DBPUIDebugMetadata(lastRunAppVersion: "")
    }

    func openSendFeedbackModal() async {}

    func applyVPNBypassSetting(_ bypass: Bool) async {}

    func removeOptOutFromDashboard(_ id: Int64) async {}

    func needBackgroundAppRefresh() async -> Bool { false }

    func enableBackgroundAppRefresh() async {}
}

private final class MockWebSettings: DataBrokerProtectionWebUIURLSettingsRepresentable {
    var customURL: String?
    var productionURL: String = ""
    var selectedURL: String = ""
    var selectedURLType: DataBrokerProtectionWebUIURLType = .production
    var selectedURLHostname: String = ""

    func setCustomURL(_ url: String) {}
    func setURLType(_ type: DataBrokerProtectionWebUIURLType) {}
}

@MainActor
struct AssistedDashboardTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func communicationUsesExplicitDelegateAndRejectsMalformedStart() async throws {
        let fixture = AssistedDashboardFixture()
        let configuration = try #require(fixture.model.setupCommunicationLayer())
        let controller = try #require(configuration.userContentController as? DBPUIUserContentController)
        let layer = controller.dbpUIUserScripts.dbpUICommunicationLayer
        let featureConfig = try await layer.handler(forMethodNamed: DBPUIReceivedMethodName.getFeatureConfig.rawValue)?([:], WKScriptMessage.mock())
        #expect((featureConfig as? DBPUIFeatureConfigurationResponse)?.userAssistanceEnabled == true)
        let list = try await layer.handler(forMethodNamed: DBPUIReceivedMethodName.getAssistedOptOuts.rawValue)?([:], WKScriptMessage.mock())
        #expect(list as? AssistedOptOutList == fixture.agent.list)
        let start = try #require(layer.handler(forMethodNamed: DBPUIReceivedMethodName.startAssistedOptOut.rawValue))
        await #expect(throws: (any Error).self) { try await start(["id": 42], WKScriptMessage.mock()) }
        _ = try await start(["id": "1-1-1"], WKScriptMessage.mock())
        #expect(fixture.agent.startedIDs == ["1-1-1"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func visiblePollingPushesChangesPreservesFailedLoadsAndClearsWhenDisabled() async throws {
        let fixture = AssistedDashboardFixture()
        _ = try #require(fixture.model.setupCommunicationLayer())
        let webView = AssistedRecordingWebView()
        let initialPush = XCTestExpectation(description: "Initial list pushed")
        webView.onPush = { initialPush.fulfill() }
        await fixture.model.pollAssistedOptOuts(in: webView)
        #expect(await XCTWaiter.fulfillment(of: [initialPush], timeout: 5) == .completed)
        #expect(webView.scripts.count == 1)
        #expect(webView.scripts[0].contains("assistedOptOutsDidChange"))
        #expect(webView.scripts[0].contains("1-1-1"))
        webView.onPush = nil
        await fixture.model.pollAssistedOptOuts(in: webView)
        #expect(webView.scripts.count == 1)
        let lastGoodList = fixture.agent.list
        fixture.agent.list = nil
        await fixture.model.pollAssistedOptOuts(in: webView)
        #expect(await fixture.model.getAssistedOptOuts() == lastGoodList)
        #expect(webView.scripts.count == 1)
        let requestsBeforeDisable = fixture.agent.requests
        fixture.flagger.isUserAssistanceOn = false
        let clearedPush = XCTestExpectation(description: "Disabled list cleared")
        webView.onPush = { clearedPush.fulfill() }
        await fixture.model.pollAssistedOptOuts(in: webView)
        #expect(await XCTWaiter.fulfillment(of: [clearedPush], timeout: 5) == .completed)
        #expect(fixture.agent.requests == requestsBeforeDisable)
        #expect(webView.scripts.count == 2)
        #expect(!webView.scripts[1].contains("1-1-1"))
        #expect(await fixture.model.getAssistedOptOuts().optOuts.isEmpty)
        fixture.flagger.isUserAssistanceOn = true
        fixture.agent.list = lastGoodList
        let restoredPush = XCTestExpectation(description: "Enabled list restored")
        webView.onPush = { restoredPush.fulfill() }
        await fixture.model.pollAssistedOptOuts(in: webView)
        #expect(await XCTWaiter.fulfillment(of: [restoredPush], timeout: 5) == .completed)
        #expect(webView.scripts.count == 3)
        webView.pollingWindow.visibleForPolling = false
        let requestsBeforeHide = fixture.agent.requests
        await fixture.model.pollAssistedOptOuts(in: webView)
        #expect(fixture.agent.requests == requestsBeforeHide)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func pollingStopsAndDoesNotRetainViewModel() async throws {
        let fixture = AssistedDashboardFixture()
        let webView = AssistedRecordingWebView()
        let firstPoll = XCTestExpectation(description: "Timer polled")
        fixture.agent.onGet = { firstPoll.fulfill() }
        fixture.model.startAssistedOptOutsPolling(in: webView)
        #expect(await XCTWaiter.fulfillment(of: [firstPoll], timeout: 5) == .completed)
        fixture.model.stopAssistedOptOutsPolling()
        let noFurtherPoll = XCTestExpectation(description: "Stopped timer does not poll")
        noFurtherPoll.isInverted = true
        fixture.agent.onGet = { noFurtherPoll.fulfill() }
        #expect(await XCTWaiter.fulfillment(of: [noFurtherPoll], timeout: 2.2) == .completed)
        var model: DBPUIViewModel? = fixture.makeModel()
        weak var weakModel = model
        model?.startAssistedOptOutsPolling(in: webView)
        model = nil
        await Task.yield()
        #expect(weakModel == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func dashboardRemovalNotifiesAgentOnlyAfterSuccessfulWrite(succeeds: Bool) throws {
        let fixture = AssistedDashboardFixture()
        _ = try #require(fixture.model.setupCommunicationLayer())
        fixture.database.extractedProfileToReturn = .mockWithoutRemovedDate
        if !succeeds { fixture.database.addHistoryEventError = DataBrokerProtectionError.jobTimeout }
        fixture.dataManager.willRemoveOptOutFromDashboard(1)
        #expect(fixture.agent.invalidations == (succeeds ? 1 : 0))
        #expect(fixture.database.optOutEvents.last?.type == (succeeds ? .matchRemovedByUser : nil))
        #expect(fixture.agent.profileSavedCalls == 0)
    }
}

@MainActor
private final class AssistedDashboardFixture {
    let agent = AssistedAgentInterface()
    let flagger = MockDBPFeatureFlagger(isUserAssistanceOn: true)
    let database = MockDatabase()
    let privacyConfig = PrivacyConfigurationManagingMock()
    lazy var dataManager = DataBrokerProtectionDataManager(database: database)
    lazy var model = makeModel()

    func makeModel() -> DBPUIViewModel {
        DBPUIViewModel(dataManager: dataManager, agentInterface: agent, webUISettings: MockWebSettings(),
                       pixelHandler: MockDataBrokerProtectionPixelsHandler(), privacyConfig: privacyConfig, prefs: .mock,
                       dbpSettings: DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: "AssistedDashboardTests.\(UUID().uuidString)")!),
                       userAssistanceFlagger: flagger)
    }
}

private final class AssistedAgentInterface: DataBrokerProtectionAppToAgentInterface {
    var list: AssistedOptOutList? = .init(optOuts: [.init(id: "1-1-1", dataBroker: .init(name: "Broker", url: "testbroker.com"), state: .waiting)])
    var requests = 0
    var startedIDs: [String] = []
    var invalidations = 0
    var profileSavedCalls = 0
    var onGet: (() -> Void)?
    func getAssistedOptOuts() async -> AssistedOptOutList? {
        requests += 1
        onGet?()
        return list
    }
    func startAssistedOptOut(id: String) { startedIDs.append(id) }
    func assistedOptOutDataDidChange() { invalidations += 1 }
    func profileSaved() async { profileSavedCalls += 1 }
    func appLaunched() async {}
    func openBrowser(domain: String) {}
    func startImmediateOperations(showWebView: Bool) {}
    func startScheduledOperations(showWebView: Bool) {}
    func runAllOptOuts(showWebView: Bool) {}
    func checkForEmailConfirmationData() async {}
    func runEmailConfirmationOperations(showWebView: Bool) async {}
    func getDebugMetadata() async -> DBPBackgroundAgentMetadata? { nil }
    func startDebugServer() async -> Bool { false }
    func stopDebugServer() {}
}

@MainActor
private final class AssistedVisibilityWindow: NSWindow {
    var visibleForPolling = true
    override var occlusionState: NSWindow.OcclusionState { visibleForPolling ? .visible : [] }
}

@MainActor
private final class AssistedRecordingWebView: WKWebView {
    let pollingWindow = AssistedVisibilityWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    var scripts: [String] = []
    var onPush: (() -> Void)?
    override var window: NSWindow? { pollingWindow }
    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        scripts.append(javaScriptString)
        onPush?()
        completionHandler?(nil, nil)
    }
}
