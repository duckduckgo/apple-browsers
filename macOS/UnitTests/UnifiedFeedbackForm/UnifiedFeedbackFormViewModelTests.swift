//
//  UnifiedFeedbackFormViewModelTests.swift
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

import XCTest
import Subscription
import SubscriptionTestingUtilities
import NetworkingTestingUtils
@testable import DuckDuckGo_Privacy_Browser
@testable import Networking

final class UnifiedFeedbackFormViewModelTests: XCTestCase {
    enum Error: String, Swift.Error {
        case generic
    }

    func testWhenCreatingViewModel_ThenInitialStateIsFeedbackPending() throws {
        let collector = MockVPNMetadataCollector()
        let sender = MockVPNFeedbackSender()
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: collector,
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger())

        XCTAssertEqual(viewModel.viewState, .feedbackPending)
    }

    func testGivenNoEmail_WhenSendingFeedbackSucceeds_ThenFeedbackIsSent() async throws {
        let collector = MockVPNMetadataCollector()
        let sender = MockVPNFeedbackSender()
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: collector,
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger())
        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        let text = "Some feedback report text"
        viewModel.feedbackFormText = text

        XCTAssertFalse(sender.sentMetadata)
        await viewModel.process(action: .submit)
        XCTAssertTrue(sender.sentMetadata)
        XCTAssertEqual(sender.receivedData!.4, text)
    }

    func testGivenEmail_WhenSendingFeedbackSucceeds_ThenFeedbackIsSent() async throws {
        let collector = MockVPNMetadataCollector()
        let sender = MockVPNFeedbackSender()
        let payload = UnifiedFeedbackFormViewModel.Response(message: "something", error: nil)
        let response = APIResponseV2(data: try! JSONEncoder().encode(payload), httpResponse: HTTPURLResponse())
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .success(response)),
                                                     vpnMetadataCollector: collector,
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger())
        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.userEmail = "hello@example.com"
        let text = "Some feedback report text"
        viewModel.feedbackFormText = text

        XCTAssertFalse(sender.sentMetadata)
        await viewModel.process(action: .submit)
        XCTAssertTrue(sender.sentMetadata)
        XCTAssertEqual(sender.receivedData!.4, text)
    }

    func testWhenSendingFeedbackFails_ThenFeedbackIsNotSent() async throws {
        let collector = MockVPNMetadataCollector()
        let sender = MockVPNFeedbackSender()
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: collector,
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger())
        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        let text = "Some feedback report text"
        viewModel.feedbackFormText = text
        sender.throwErrorWhenSending = true

        XCTAssertFalse(sender.sentMetadata)
        await viewModel.process(action: .submit)
        XCTAssertFalse(sender.sentMetadata)
        XCTAssertEqual(viewModel.viewState, .feedbackSendingFailed)
    }

    func testGivenInvalidEmail_WhenSendingFeedbackFails_ThenFeedbackIsNotSent() async throws {
        let collector = MockVPNMetadataCollector()
        let sender = MockVPNFeedbackSender()
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: collector,
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger())
        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.userEmail = "invalid-email"
        let text = "Some feedback report text"
        viewModel.feedbackFormText = text
        sender.throwErrorWhenSending = true

        XCTAssertFalse(sender.sentMetadata)
        await viewModel.process(action: .submit)
        XCTAssertFalse(sender.sentMetadata)
        XCTAssertEqual(viewModel.viewState, .feedbackSendingFailed)
    }

    func testGivenValidEmail_WhenSendingFeedbackFails_ThenFeedbackIsNotSent() async throws {
        let collector = MockVPNMetadataCollector()
        let sender = MockVPNFeedbackSender()
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: collector,
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger())
        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.userEmail = "hello@example.com"
        let text = "Some feedback report text"
        viewModel.feedbackFormText = text
        sender.throwErrorWhenSending = true

        XCTAssertFalse(sender.sentMetadata)
        await viewModel.process(action: .submit)
        XCTAssertFalse(sender.sentMetadata)
        XCTAssertEqual(viewModel.viewState, .feedbackSendingFailed)
    }

    func testWhenCancelActionIsReceived_ThenViewModelSendsCancelActionToDelegate() async throws {
        let collector = MockVPNMetadataCollector()
        let sender = MockVPNFeedbackSender()
        let delegate = MockVPNFeedbackFormViewModelDelegate()
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: collector,
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger())
        viewModel.delegate = delegate

        XCTAssertFalse(delegate.receivedDismissedViewCallback)
        await viewModel.process(action: .cancel)
        XCTAssertTrue(delegate.receivedDismissedViewCallback)
    }

    func disabledTestWhenDuckAiFeatureIsEnabledAndSubscriptionIncludesPaidAIChat_ThenDuckAiCategoryIsAvailable() async throws {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.subscriptionFeatures = [.paidAIChat]
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.paidAIChat]

        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: subscriptionManager,
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: MockVPNMetadataCollector(),
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: MockVPNFeedbackSender(),
                                                     featureFlagger: featureFlagger)

        let expectation = XCTestExpectation(description: "Wait for DuckAi category to become available")
        let pollingInterval: TimeInterval = 0.1
        Task {
            while !viewModel.availableCategories.contains(.duckAi) {
                try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertTrue(viewModel.availableCategories.contains(.duckAi))
    }

    func testWhenDuckAiFeatureIsDisabled_ThenDuckAiCategoryIsNotAvailable() async throws {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.subscriptionFeatures = [.paidAIChat]
        let featureFlagger = MockFeatureFlagger()

        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: subscriptionManager,
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: MockVPNMetadataCollector(),
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: MockVPNFeedbackSender(),
                                                     featureFlagger: featureFlagger)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(viewModel.availableCategories.contains(.duckAi))
    }

    func testWhenSubscriptionDoesNotIncludePaidAIChat_ThenDuckAiCategoryIsNotAvailable() async throws {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.subscriptionFeatures = []
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.paidAIChat]

        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: subscriptionManager,
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: MockVPNMetadataCollector(),
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: MockVPNFeedbackSender(),
                                                     featureFlagger: featureFlagger)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(viewModel.availableCategories.contains(.duckAi))
    }

    func testWhenSourceIsDuckAi_ThenDefaultCategoryIsDuckAi() throws {
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: MockVPNMetadataCollector(),
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: MockVPNFeedbackSender(),
                                                     featureFlagger: MockFeatureFlagger(),
                                                     source: .duckAi)

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue

        XCTAssertEqual(viewModel.selectedCategory, UnifiedFeedbackCategory.duckAi.rawValue)
    }

    func testWhenDuckAiCategoryIsSelected_ThenSubcategoryIsSetToPaidAIChatPrompt() throws {
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .failure(Error.generic)),
                                                     vpnMetadataCollector: MockVPNMetadataCollector(),
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: MockVPNFeedbackSender(),
                                                     featureFlagger: MockFeatureFlagger())

        viewModel.selectedCategory = UnifiedFeedbackCategory.duckAi.rawValue

        XCTAssertEqual(viewModel.selectedSubcategory, PaidAIChatFeedbackSubcategory.prompt.rawValue)
    }

    func testGivenDuckAiCategorWhenSendingFeedbackSucceeds_ThenCorrectFeedbackIsSent() async throws {
        let sender = MockVPNFeedbackSender()
        let payload = UnifiedFeedbackFormViewModel.Response(message: "success", error: nil)
        let response = APIResponseV2(data: try! JSONEncoder().encode(payload), httpResponse: HTTPURLResponse())
        let viewModel = UnifiedFeedbackFormViewModel(subscriptionManager: SubscriptionManagerMock(),
                                                     apiService: MockAPIService(apiResponse: .success(response)),
                                                     vpnMetadataCollector: MockVPNMetadataCollector(),
                                                     dbpMetadataCollector: MockDBPMetadataCollector(),
                                                     defaultMetadataCollector: MockDBPMetadataCollector(),
                                                     feedbackSender: sender,
                                                     featureFlagger: MockFeatureFlagger(),
                                                     source: .ppro)

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.selectedCategory = UnifiedFeedbackCategory.duckAi.rawValue
        viewModel.selectedSubcategory = PaidAIChatFeedbackSubcategory.accessSubscriptionModels.rawValue
        viewModel.userEmail = "test@example.com"
        let text = "Duck.ai feedback text"
        viewModel.feedbackFormText = text

        await viewModel.process(action: .submit)
        XCTAssertEqual(sender.capturedSource, .ppro)
        XCTAssertEqual(sender.capturedCategory, "duckAi")
        XCTAssertEqual(sender.capturedSubcategory, "accessSubscriptionModels")
    }

}

// MARK: - Mocks

private class MockDBPMetadataCollector: UnifiedMetadataCollector {
    func collectMetadata() async -> DBPFeedbackMetadata {
        .init(vpnConnectionState: "disconnected", vpnBypassStatus: "off")
    }
}

private class MockVPNMetadataCollector: UnifiedMetadataCollector {
    var collectedMetadata = false

    func collectMetadata() async -> VPNMetadata {
        self.collectedMetadata = true

        let appInfo = VPNMetadata.AppInfo(
            appVersion: "1.2.3",
            lastAgentVersionRun: "1.2.3",
            lastExtensionVersionRun: "1.2.3",
            isInternalUser: false,
            isInApplicationsDirectory: true
        )

        let deviceInfo = VPNMetadata.DeviceInfo(
            osVersion: "14.0.0",
            buildFlavor: "dmg",
            lowPowerModeEnabled: false,
            cpuArchitecture: "arm64"
        )

        let networkInfo = VPNMetadata.NetworkInfo(currentPath: "path")

        let vpnState = VPNMetadata.VPNState(
            onboardingState: "onboarded",
            connectionState: "connected",
            lastStartErrorDescription: "none",
            lastTunnelErrorDescription: "none",
            lastKnownFailureDescription: "none",
            connectedServer: "Paoli, PA",
            connectedServerIP: "123.123.123.123"
        )

        let vpnSettingsState = VPNMetadata.VPNSettingsState(
            connectOnLoginEnabled: true,
            includeAllNetworksEnabled: true,
            enforceRoutesEnabled: true,
            excludeLocalNetworksEnabled: true,
            notifyStatusChangesEnabled: true,
            showInMenuBarEnabled: true,
            selectedServer: "server",
            selectedEnvironment: "production",
            customDNS: false
        )

        let loginItemState = VPNMetadata.LoginItemState(
            vpnMenuState: "enabled",
            vpnMenuIsRunning: true,
            notificationsAgentState: "enabled",
            notificationsAgentIsRunning: true
        )

        let privacyProInfo = VPNMetadata.PrivacyProInfo(
            hasPrivacyProAccount: true,
            hasVPNEntitlement: true
        )

        return VPNMetadata(
            appInfo: appInfo,
            deviceInfo: deviceInfo,
            networkInfo: networkInfo,
            vpnState: vpnState,
            vpnSettingsState: vpnSettingsState,
            loginItemState: loginItemState,
            privacyProInfo: privacyProInfo
        )
    }

}

private class MockVPNFeedbackSender: UnifiedFeedbackSender {
    var throwErrorWhenSending: Bool = false
    var sentMetadata: Bool = false
    var capturedSource: UnifiedFeedbackSource?
    var capturedCategory: String?
    var capturedSubcategory: String?

    var receivedData: (VPNMetadata?, UnifiedFeedbackSource, String?, String?, String?)?

    enum SomeError: Error {
        case error
    }

    func sendFeatureRequestPixel(description: String, source: UnifiedFeedbackSource) async throws {
        if throwErrorWhenSending {
            throw SomeError.error
        }

        self.sentMetadata = true
        self.receivedData = (nil, source, nil, nil, description)
    }

    func sendGeneralFeedbackPixel(description: String, source: UnifiedFeedbackSource) async throws {
        if throwErrorWhenSending {
            throw SomeError.error
        }

        self.sentMetadata = true
        self.receivedData = (nil, source, nil, nil, description)
    }

    func sendReportIssuePixel<T: UnifiedFeedbackMetadata>(source: UnifiedFeedbackSource, category: String, subcategory: String, description: String, metadata: T?) async throws {
        if throwErrorWhenSending {
            throw SomeError.error
        }
        capturedSource = source
        capturedCategory = category
        capturedSubcategory = subcategory
        self.sentMetadata = true
        self.receivedData = (metadata as? VPNMetadata, source, category, subcategory, description)
    }

    func sendFormShowPixel() {}
    func sendSubmitScreenShowPixel(source: UnifiedFeedbackSource, reportType: String, category: String, subcategory: String) {}
    func sendSubmitScreenFAQClickPixel(source: UnifiedFeedbackSource, reportType: String, category: String, subcategory: String) {}
}

private class MockVPNFeedbackFormViewModelDelegate: UnifiedFeedbackFormViewModelDelegate {
    var receivedDismissedViewCallback: Bool = false

    func feedbackViewModelDismissedView(_ viewModel: UnifiedFeedbackFormViewModel) {
        receivedDismissedViewCallback = true
    }

}

extension MockAPIService {
    convenience init(apiResponse: Result<APIResponseV2, Error>) {
        self.init { _ in apiResponse }
    }
}

extension SubscriptionManagerMock {

    convenience init() {
        let accountManager = AccountManagerMock()
        accountManager.accessToken = "token"
        self.init(accountManager: accountManager,
                  subscriptionEndpointService: SubscriptionEndpointServiceMock(),
                  authEndpointService: AuthEndpointServiceMock(),
                  storePurchaseManager: StorePurchaseManagerMock(),
                  currentEnvironment: SubscriptionEnvironment(serviceEnvironment: .production,
                                                              purchasePlatform: .appStore),
                  canPurchase: false,
                  subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock())
    }
}
