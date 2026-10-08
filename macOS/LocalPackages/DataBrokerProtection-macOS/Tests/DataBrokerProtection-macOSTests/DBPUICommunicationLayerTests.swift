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

    func testWhenHandshakeCalled_andDelegateAuthenticatedUserTrue_thenHandshakeUserDataTrue() async throws {
        // Given
        let mockDelegate = MockDelegate()
        let handshakeUserData = DBPUIHandshakeUserData(isAuthenticatedUser: true, isUserEligibleForFreeTrial: false)
        mockDelegate.handshakeUserDataToReturn = handshakeUserData
        var sut = makeSUT()
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
        var sut = makeSUT()
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
        var sut = makeSUT()
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
        var sut = makeSUT()
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

    func testWhenHandshakeCalled_andDelegateIsNil_thenHandshakeUserDataIsDefaultTrue() async throws {
        // Given
        let sut = makeSUT()
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

        let sut = makeSUT(privacyConfig: mockPrivacyConfig, vpnBypassService: mockVPNBypassService)
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

    func testWhenNoSigningKeyIsRevoked_thenHandshakeStatusIsActive() async throws {
        let sut = makeSUT()

        let result = try await sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)?(["version": 12], WKScriptMessage.mock())

        let response = try XCTUnwrap(result as? DBPUIHandshakeResponse)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.status, .active)
    }

    func testWhenSigningKeyIsRevoked_thenHandshakeStatusIsUpdateRequired() async throws {
        let privacyConfig = PrivacyConfigurationManagingMock()
        privacyConfig.setRevokedBundleSigningKeyIDs(PrivacyConfigurationManagingMock.builtInBundleSigningKeyIDs)
        let sut = makeSUT(privacyConfig: privacyConfig)

        let result = try await sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)?(["version": 12], WKScriptMessage.mock())

        let response = try XCTUnwrap(result as? DBPUIHandshakeResponse)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.status, .updateRequired)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(response), encoding: .utf8))
        XCTAssertTrue(json.contains("\"status\":\"updateRequired\""))
    }

    func testWhenOnlyAnotherKeyIsRevoked_thenHandshakeStatusIsActive() async throws {
        let privacyConfig = PrivacyConfigurationManagingMock()
        privacyConfig.setRevokedBundleSigningKeyIDs([String(repeating: "0", count: 64)])
        let sut = makeSUT(privacyConfig: privacyConfig)

        let result = try await sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)?(["version": 12], WKScriptMessage.mock())

        XCTAssertEqual(try XCTUnwrap(result as? DBPUIHandshakeResponse).status, .active)
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

    func testWhenRevokedKeyIsDroppedWhileRunning_thenDashboardResumes() async throws {
        let privacyConfig = PrivacyConfigurationManagingMock()
        privacyConfig.setRevokedBundleSigningKeyIDs(PrivacyConfigurationManagingMock.builtInBundleSigningKeyIDs)
        let mockDelegate = MockDelegate()
        mockDelegate.startScanAndOptOutResult = true
        var sut = makeSUT(privacyConfig: privacyConfig)
        sut.delegate = mockDelegate
        let handshake = sut.handler(forMethodNamed: DBPUIReceivedMethodName.handshake.rawValue)

        let pausedResult = try await handshake?(["version": 12], WKScriptMessage.mock())
        XCTAssertEqual(try XCTUnwrap(pausedResult as? DBPUIHandshakeResponse).status, .updateRequired)

        privacyConfig.setRevokedBundleSigningKeyIDs([])

        let resumedResult = try await handshake?(["version": 12], WKScriptMessage.mock())
        XCTAssertEqual(try XCTUnwrap(resumedResult as? DBPUIHandshakeResponse).status, .active)
        let initialScanState = try await sut.handler(forMethodNamed: DBPUIReceivedMethodName.initialScanStatus.rawValue)?([:], WKScriptMessage.mock())
        XCTAssertTrue(initialScanState is DBPUIInitialScanState)
        let startResult = try await sut.handler(forMethodNamed: DBPUIReceivedMethodName.startScanAndOptOut.rawValue)?([:], WKScriptMessage.mock())
        XCTAssertEqual(try XCTUnwrap(startResult as? DBPUIStandardResponse).success, true)
        XCTAssertTrue(mockDelegate.startScanAndOptOutCalled)
    }

    // MARK: - Helpers

    private func makeSUT(privacyConfig: PrivacyConfigurationManagingMock = PrivacyConfigurationManagingMock(),
                         vpnBypassService: VPNBypassServiceProvider? = nil) -> DBPUICommunicationLayer {
        let settings = DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: "DBPUICommunicationLayerTests.\(UUID().uuidString)")!)
        return DBPUICommunicationLayer(webURLSettings: MockWebSettings(),
                                       vpnBypassService: vpnBypassService,
                                       privacyConfig: privacyConfig,
                                       keyRevocationChecker: BrokerBundleKeyRevocationChecker(privacyConfigurationManager: privacyConfig,
                                                                                              settings: settings))
    }
}

// MARK: - Mock Classes

private final class MockDelegate: DBPUICommunicationDelegate {
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
