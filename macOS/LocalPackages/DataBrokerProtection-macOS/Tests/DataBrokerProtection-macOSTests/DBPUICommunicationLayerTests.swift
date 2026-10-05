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
        var sut = DBPUICommunicationLayer(webURLSettings: MockWebSettings(), handshakeDelegate: mockDelegate, privacyConfig: PrivacyConfigurationManagingMock())
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
        var sut = DBPUICommunicationLayer(webURLSettings: MockWebSettings(), handshakeDelegate: mockDelegate, privacyConfig: PrivacyConfigurationManagingMock())
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
        var sut = DBPUICommunicationLayer(webURLSettings: MockWebSettings(), handshakeDelegate: mockDelegate, privacyConfig: PrivacyConfigurationManagingMock())
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
        var sut = DBPUICommunicationLayer(webURLSettings: MockWebSettings(), handshakeDelegate: mockDelegate, privacyConfig: PrivacyConfigurationManagingMock())
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
        let sut = DBPUICommunicationLayer(webURLSettings: MockWebSettings(), handshakeDelegate: mockDelegate, privacyConfig: PrivacyConfigurationManagingMock())
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
        let sut = DBPUICommunicationLayer(webURLSettings: MockWebSettings(),
                                          handshakeDelegate: mockDelegate,
                                          vpnBypassService: mockVPNBypassService,
                                          privacyConfig: mockPrivacyConfig)
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
                       prefs: .mock)
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
    func startScanAndOptOut() -> Bool { false }

    func getInitialScanState() async -> DBPUIInitialScanState {
        DBPUIInitialScanState(resultsFound: [], scanProgress: .init(currentScans: 0, totalScans: 0, scannedBrokers: []))
    }

    func getMaintenanceScanState() async -> DBPUIScanAndOptOutMaintenanceState {
        DBPUIScanAndOptOutMaintenanceState(
            inProgressOptOuts: [],
            completedOptOuts: [],
            scanSchedule: .init(lastScan: .init(date: 2, dataBrokers: []), nextScan: .init(date: 2, dataBrokers: [])),
            scanHistory: .init(sitesScanned: 2)
        )
    }

    func getDataBrokers() async -> [DBPUIDataBroker] {
        []
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
