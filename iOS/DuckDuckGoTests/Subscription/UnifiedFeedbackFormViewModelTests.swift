//
//  UnifiedFeedbackFormViewModelTests.swift
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

import Testing
import Networking
import Subscription
import SubscriptionTestingUtilities
import NetworkingTestingUtils
@testable import DuckDuckGo
import Foundation

struct UnifiedFeedbackFormViewModelTests {

    // MARK: - Test Fixtures
    enum TestError: Swift.Error {
        case generic
    }

    private func makeViewModel(
        subscriptionFeatures: [Entitlement.ProductName] = [],
        isPaidAIChatFeatureEnabled: Bool = false,
        apiResponse: Result<APIResponseV2, Swift.Error> = .failure(TestError.generic),
        source: UnifiedFeedbackFormViewModel.Source = .unknown,
        feedbackSender: MockFeedbackSender = MockFeedbackSender()
    ) -> UnifiedFeedbackFormViewModel {

        let subscriptionManager = makeSubscriptionManager(features: subscriptionFeatures)

        // Configure API service with requestHandler
        let apiService = MockAPIService { request in
            // Only respond to feedback endpoint requests
            if request.url!.absoluteString.contains("feedback") {
                return apiResponse
            }
            return .failure(TestError.generic)
        }

        let viewModel = UnifiedFeedbackFormViewModel(
            subscriptionManager: subscriptionManager,
            apiService: apiService,
            vpnMetadataCollector: MockUnifiedMetadataCollector(),
            dbpMetadataCollector: MockUnifiedMetadataCollector(),
            defaultMetadatCollector: MockUnifiedMetadataCollector(),
            feedbackSender: feedbackSender,
            isPaidAIChatFeatureEnabled: { isPaidAIChatFeatureEnabled },
            source: source
        )

        return viewModel
    }

    private func makeSubscriptionManager(features: [Entitlement.ProductName]) -> SubscriptionManagerMock {
        let accountManager = AccountManagerMock()
        accountManager.accessToken = "test-token"

        let manager = SubscriptionManagerMock(
            accountManager: accountManager,
            subscriptionEndpointService: SubscriptionEndpointServiceMock(),
            authEndpointService: AuthEndpointServiceMock(),
            storePurchaseManager: StorePurchaseManagerMock(),
            currentEnvironment: SubscriptionEnvironment(
                serviceEnvironment: .production,
                purchasePlatform: .appStore
            ),
            canPurchase: false,
            subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock()
        )

        manager.subscriptionFeatures = features
        return manager
    }

    private func makeSuccessfulAPIResponse() throws -> Result<APIResponseV2, Swift.Error> {
        struct TestResponse: Codable {
            let message: String?
            let error: String?
        }

        let responseData = TestResponse(message: "Success", error: nil)
        let data = try JSONEncoder().encode(responseData)
        let response = APIResponseV2(data: data, httpResponse: HTTPURLResponse())
        return .success(response)
    }

    // MARK: - Initialization Tests

    @Test func testInitialization_SetsInitialState() async throws {
        let viewModel = makeViewModel()

        #expect(viewModel.viewState == .feedbackPending)
        #expect(viewModel.feedbackFormText.isEmpty)
        #expect(viewModel.submitButtonEnabled == false)
        #expect(viewModel.selectedReportType == nil)
        #expect(viewModel.selectedCategory == nil)
        #expect(viewModel.selectedSubcategory == nil)
        #expect(viewModel.userEmail.isEmpty)
    }

    @Test func testInitialization_DefaultCategoriesIncludeSubscription() async throws {
        let viewModel = makeViewModel()

        // Wait for async category setup
        try await waitForCondition {
            viewModel.availableCategories.contains(.subscription)
        }

        #expect(viewModel.availableCategories.contains(.subscription))
    }

    // MARK: - Category Tests

    @Test func testDuckAiCategory_WhenFeatureEnabledAndSubscriptionIncludesPaidAIChat_IsAvailable() async throws {
        let viewModel = makeViewModel(
            subscriptionFeatures: [.paidAIChat],
            isPaidAIChatFeatureEnabled: true
        )

        // Wait for DuckAi category to become available
        try await waitForCondition {
            viewModel.availableCategories.contains(.duckAi)
        }
        
        #expect(viewModel.availableCategories.contains(.duckAi))
    }

    @Test func testDuckAiCategory_WhenFeatureDisabled_IsNotAvailable() async throws {
        let viewModel = makeViewModel(
            subscriptionFeatures: [.paidAIChat],
            isPaidAIChatFeatureEnabled: false
        )

        // Wait for categories to be processed, then verify DuckAi is not included
        try await waitForCondition {
            !viewModel.availableCategories.isEmpty
        }
        
        #expect(!viewModel.availableCategories.contains(.duckAi))
    }

    @Test func testDuckAiCategory_WhenSubscriptionDoesNotIncludePaidAIChat_IsNotAvailable() async throws {
        let viewModel = makeViewModel(
            subscriptionFeatures: [],
            isPaidAIChatFeatureEnabled: true
        )

        // Wait for categories to be processed, then verify DuckAi is not included
        try await waitForCondition {
            !viewModel.availableCategories.isEmpty
        }
        
        #expect(!viewModel.availableCategories.contains(.duckAi))
    }

    @Test func testVPNCategory_WhenNetworkProtectionFeatureAvailable_IsIncluded() async throws {
        let viewModel = makeViewModel(
            subscriptionFeatures: [.networkProtection]
        )

        // Wait for VPN category to become available
        try await waitForCondition {
            viewModel.availableCategories.contains(.vpn)
        }

        #expect(viewModel.availableCategories.contains(.vpn))
    }

    @Test func testPIRCategory_WhenDataBrokerProtectionFeatureAvailable_IsIncluded() async throws {
        let viewModel = makeViewModel(
            subscriptionFeatures: [.dataBrokerProtection]
        )

        // Wait for PIR category to become available
        try await waitForCondition {
            viewModel.availableCategories.contains(.pir)
        }

        #expect(viewModel.availableCategories.contains(.pir))
    }

    @Test func testITRCategory_WhenIdentityTheftRestorationFeatureAvailable_IsIncluded() async throws {
        let viewModel = makeViewModel(
            subscriptionFeatures: [.identityTheftRestoration]
        )

        // Wait for ITR category to become available
        try await waitForCondition {
            viewModel.availableCategories.contains(.itr)
        }

        #expect(viewModel.availableCategories.contains(.itr))
    }

    // MARK: - Subcategory Tests

    @Test func testSubscriptionSubcategories_HaveCorrectDisplayNames() {
        #expect(PrivacyProFeedbackSubcategory.otp.displayName == UserText.pproFeedbackFormCategoryOTP)
        #expect(PrivacyProFeedbackSubcategory.somethingElse.displayName == UserText.pproFeedbackFormCategoryOther)
    }

    @Test func testSubscriptionSubcategories_HaveCorrectFAQUrls() {
        #expect(PrivacyProFeedbackSubcategory.otp.url.absoluteString.contains("payments") == true)
        #expect(PrivacyProFeedbackSubcategory.somethingElse.url.absoluteString.contains("payments") == true)
    }

    @Test func testVPNSubcategories_HaveCorrectDisplayNames() {
        #expect(VPNFeedbackSubcategory.unableToInstall.displayName == UserText.vpnFeedbackFormCategoryUnableToInstall)
        #expect(VPNFeedbackSubcategory.failsToConnect.displayName == UserText.vpnFeedbackFormCategoryFailsToConnect)
        #expect(VPNFeedbackSubcategory.tooSlow.displayName == UserText.vpnFeedbackFormCategoryTooSlow)
        #expect(VPNFeedbackSubcategory.issueWithAppOrWebsite.displayName == UserText.vpnFeedbackFormCategoryIssuesWithApps)
        #expect(VPNFeedbackSubcategory.appCrashesOrFreezes.displayName == UserText.vpnFeedbackFormCategoryBrowserCrashOrFreeze)
        #expect(VPNFeedbackSubcategory.cantConnectToLocalDevice.displayName == UserText.vpnFeedbackFormCategoryLocalDeviceConnectivity)
        #expect(VPNFeedbackSubcategory.somethingElse.displayName == UserText.vpnFeedbackFormCategoryOther)
    }

    @Test func testVPNSubcategories_HaveCorrectFAQUrls() {
        // Most VPN subcategories should point to troubleshooting page
        let troubleshootingUrl = "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/vpn/troubleshooting/"

        #expect(VPNFeedbackSubcategory.unableToInstall.url.absoluteString == troubleshootingUrl)
        #expect(VPNFeedbackSubcategory.failsToConnect.url.absoluteString == troubleshootingUrl)
        #expect(VPNFeedbackSubcategory.tooSlow.url.absoluteString == troubleshootingUrl)
        #expect(VPNFeedbackSubcategory.issueWithAppOrWebsite.url.absoluteString == troubleshootingUrl)
        #expect(VPNFeedbackSubcategory.appCrashesOrFreezes.url.absoluteString == troubleshootingUrl)
        #expect(VPNFeedbackSubcategory.cantConnectToLocalDevice.url.absoluteString == troubleshootingUrl)

        // "Something else" should point to general VPN page
        #expect(VPNFeedbackSubcategory.somethingElse.url.absoluteString == "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/vpn/")
    }

    @Test func testPIRSubcategories_HaveCorrectDisplayNames() {
        #expect(PIRFeedbackSubcategory.nothingOnSpecificSite.displayName == UserText.pirFeedbackFormCategoryNothingOnSpecificSite)
        #expect(PIRFeedbackSubcategory.notMe.displayName == UserText.pirFeedbackFormCategoryNotMe)
        #expect(PIRFeedbackSubcategory.scanStuck.displayName == UserText.pirFeedbackFormCategoryScanStuck)
        #expect(PIRFeedbackSubcategory.removalStuck.displayName == UserText.pirFeedbackFormCategoryRemovalStuck)
        #expect(PIRFeedbackSubcategory.somethingElse.displayName == UserText.pirFeedbackFormCategoryOther)
    }

    @Test func testPIRSubcategories_HaveCorrectFAQUrls() {
        let removalProcessUrl = "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/personal-information-removal/removal-process/"

        #expect(PIRFeedbackSubcategory.nothingOnSpecificSite.url.absoluteString == removalProcessUrl)
        #expect(PIRFeedbackSubcategory.notMe.url.absoluteString == removalProcessUrl)
        #expect(PIRFeedbackSubcategory.scanStuck.url.absoluteString == removalProcessUrl)
        #expect(PIRFeedbackSubcategory.removalStuck.url.absoluteString == removalProcessUrl)

        // "Something else" should point to general PIR page
        #expect(PIRFeedbackSubcategory.somethingElse.url.absoluteString == "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/personal-information-removal/")
    }

    @Test func testITRSubcategories_HaveCorrectDisplayNames() {
        #expect(ITRFeedbackSubcategory.accessCode.displayName == UserText.itrFeedbackFormCategoryAccessCode)
        #expect(ITRFeedbackSubcategory.cantContactAdvisor.displayName == UserText.itrFeedbackFormCategoryCantContactAdvisor)
        #expect(ITRFeedbackSubcategory.advisorUnhelpful.displayName == UserText.itrFeedbackFormCategoryUnhelpful)
        #expect(ITRFeedbackSubcategory.somethingElse.displayName == UserText.itrFeedbackFormCategorySomethingElse)
    }

    @Test func testITRSubcategories_HaveCorrectFAQUrls() {
        let itrGeneralUrl = "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/identity-theft-restoration/"
        let irisUrl = "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/identity-theft-restoration/iris/"

        #expect(ITRFeedbackSubcategory.accessCode.url.absoluteString == itrGeneralUrl)
        #expect(ITRFeedbackSubcategory.cantContactAdvisor.url.absoluteString == irisUrl)
        #expect(ITRFeedbackSubcategory.advisorUnhelpful.url.absoluteString == itrGeneralUrl)
        #expect(ITRFeedbackSubcategory.somethingElse.url.absoluteString == itrGeneralUrl)
    }

    @Test func testDuckAiSubcategories_HaveCorrectDisplayNames() {
        #expect(PaidAIChatFeedbackSubcategory.accessSubscriptionModels.displayName == UserText.paidDuckAIFeedbackFormCategoryAccessSubscriptionModels)
        #expect(PaidAIChatFeedbackSubcategory.loginThirdPartyBrowser.displayName == UserText.paidDuckAIFeedbackFormCategoryLoginThirdPartyBrowser)
        #expect(PaidAIChatFeedbackSubcategory.somethingElse.displayName == UserText.paidDuckAIFeedbackFormCategorySomethingElse)
    }

    @Test func testDuckAiSubcategories_HaveCorrectFAQUrls() {
        let accessSubscriptionModelsUrl = "https://duckduckgo.com/duckduckgo-help-pages/duckai/access-subscriber-AI-models/"
        let loginThirdPartyBrowserUrl = "https://duckduckgo.com/duckduckgo-help-pages/privacy-pro/activating/"
        let somethingElseUrl = "https://duckduckgo.com/duckduckgo-help-pages/duckai/"

        #expect(PaidAIChatFeedbackSubcategory.accessSubscriptionModels.url.absoluteString == accessSubscriptionModelsUrl)
        #expect(PaidAIChatFeedbackSubcategory.loginThirdPartyBrowser.url.absoluteString == loginThirdPartyBrowserUrl)
        #expect(PaidAIChatFeedbackSubcategory.somethingElse.url.absoluteString == somethingElseUrl)
    }

    @Test func testSubcategorySelection_ResetsWhenCategoryChanges() {
        let viewModel = makeViewModel()

        // Set initial category and subcategory
        viewModel.selectedCategory = UnifiedFeedbackCategory.subscription.rawValue
        viewModel.selectedSubcategory = PrivacyProFeedbackSubcategory.otp.rawValue

        #expect(viewModel.selectedSubcategory == "otp")

        // Change category should reset subcategory
        viewModel.selectedCategory = UnifiedFeedbackCategory.vpn.rawValue

        #expect(viewModel.selectedSubcategory == "")
    }

    @Test func testFeedbackTextReset_WhenSubcategoryChanges() {
        let viewModel = makeViewModel()

        // Set feedback text
        viewModel.feedbackFormText = "Some feedback text"
        #expect(viewModel.feedbackFormText == "Some feedback text")

        // Change subcategory should reset feedback text
        viewModel.selectedSubcategory = PrivacyProFeedbackSubcategory.otp.rawValue

        #expect(viewModel.feedbackFormText.isEmpty)
    }

    @Test func testCategorySelection_ResetsWhenReportTypeChanges() {
        let viewModel = makeViewModel()

        // Set initial report type and category
        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.selectedCategory = UnifiedFeedbackCategory.subscription.rawValue

        #expect(viewModel.selectedCategory == "subscription")

        // Change report type should reset category
        viewModel.selectedReportType = UnifiedFeedbackReportType.general.rawValue

        #expect(viewModel.selectedCategory == "")
    }

    // MARK: - Submit Button State Tests

    @Test func testSubmitButton_WhenFormEmpty_IsDisabled() {
        let viewModel = makeViewModel()

        #expect(viewModel.submitButtonEnabled == false)
    }

    @Test func testSubmitButton_WhenFormHasTextButInvalidEmail_IsDisabled() {
        let viewModel = makeViewModel()

        viewModel.feedbackFormText = "Some feedback"
        viewModel.userEmail = "invalid-email"

        #expect(viewModel.submitButtonEnabled == false)
    }

    @Test func testSubmitButton_WhenFormHasTextAndValidEmail_IsEnabled() {
        let viewModel = makeViewModel()

        viewModel.feedbackFormText = "Some feedback"
        viewModel.userEmail = "test@example.com"

        #expect(viewModel.submitButtonEnabled == true)
    }

    @Test func testSubmitButton_WhenFormHasTextAndNoEmail_IsEnabled() {
        let viewModel = makeViewModel()

        viewModel.feedbackFormText = "Some feedback"
        viewModel.userEmail = ""

        #expect(viewModel.submitButtonEnabled == true)
    }

    // MARK: - Feedback Submission Tests

    @Test func testSubmitGeneralFeedback_SendsCorrectPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.general.rawValue
        viewModel.feedbackFormText = "General feedback text"

        await viewModel.process(action: .submit)

        #expect(sender.generalFeedbackPixelSent)
        #expect(sender.lastGeneralFeedbackDescription == "General feedback text")
    }

    @Test func testSubmitFeatureRequest_SendsCorrectPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.requestFeature.rawValue
        viewModel.feedbackFormText = "Feature request text"

        await viewModel.process(action: .submit)

        #expect(sender.featureRequestPixelSent)
        #expect(sender.lastFeatureRequestDescription == "Feature request text")
    }

    @Test func testSubmitReportIssue_SendsCorrectPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.selectedCategory = UnifiedFeedbackCategory.subscription.rawValue
        viewModel.selectedSubcategory = PrivacyProFeedbackSubcategory.otp.rawValue
        viewModel.feedbackFormText = "Issue report text"

        await viewModel.process(action: .submit)

        #expect(sender.reportIssuePixelSent)
        #expect(sender.lastReportIssueDescription == "Issue report text")
        #expect(sender.lastReportIssueCategory == "subscription")
        #expect(sender.lastReportIssueSubcategory == "otp")
    }

    @Test func testSubmitDuckAiIssue_SendsCorrectPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(
            subscriptionFeatures: [.paidAIChat],
            isPaidAIChatFeatureEnabled: true,
            feedbackSender: sender
        )

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.selectedCategory = UnifiedFeedbackCategory.duckAi.rawValue
        viewModel.selectedSubcategory = PaidAIChatFeedbackSubcategory.accessSubscriptionModels.rawValue
        viewModel.feedbackFormText = "Duck.ai issue text"

        await viewModel.process(action: .submit)

        #expect(sender.reportIssuePixelSent)
        #expect(sender.lastReportIssueDescription == "Duck.ai issue text")
        #expect(sender.lastReportIssueCategory == "duckAi")
        #expect(sender.lastReportIssueSubcategory == "accessSubscriptionModels")
    }

    @Test func testSubmitFeedback_WhenSuccessful_UpdatesStateToSent() async throws {
        let successfulResponse = try makeSuccessfulAPIResponse()
        let viewModel = makeViewModel(apiResponse: successfulResponse)

        viewModel.selectedReportType = UnifiedFeedbackReportType.general.rawValue
        viewModel.feedbackFormText = "Test feedback"

        await viewModel.process(action: .submit)

        #expect(viewModel.viewState == .feedbackSent)
    }

    @Test func testSubmitFeedback_WhenFails_UpdatesStateToFailed() async throws {
        let sender = MockFeedbackSender()
        sender.shouldThrowError = true

        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.general.rawValue
        viewModel.feedbackFormText = "Test feedback"

        await viewModel.process(action: .submit)

        #expect(viewModel.viewState == .feedbackSendingFailed)
    }

    // MARK: - Pixel Tracking Tests

    @Test func testReportShow_SendsFormShowPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        await viewModel.process(action: .reportShow)

        #expect(sender.formShowPixelSent)
    }

    @Test func testReportActions_SendsActionsScreenShowPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        await viewModel.process(action: .reportActions)

        #expect(sender.actionsScreenShowPixelSent)
    }

    @Test func testReportCategory_SendsCategoryScreenShowPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue

        await viewModel.process(action: .reportCategory)

        #expect(sender.categoryScreenShowPixelSent)
    }

    @Test func testReportSubcategory_SendsSubcategoryScreenShowPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.selectedCategory = UnifiedFeedbackCategory.subscription.rawValue

        await viewModel.process(action: .reportSubcategory)

        #expect(sender.subcategoryScreenShowPixelSent)
    }

    @Test func testReportSubmitShow_SendsSubmitScreenShowPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.selectedCategory = UnifiedFeedbackCategory.subscription.rawValue
        viewModel.selectedSubcategory = PrivacyProFeedbackSubcategory.otp.rawValue

        await viewModel.process(action: .reportSubmitShow)

        #expect(sender.submitScreenShowPixelSent)
    }

    @Test func testReportFAQClick_SendsFAQClickPixel() async throws {
        let sender = MockFeedbackSender()
        let viewModel = makeViewModel(feedbackSender: sender)

        viewModel.selectedReportType = UnifiedFeedbackReportType.reportIssue.rawValue
        viewModel.selectedCategory = UnifiedFeedbackCategory.subscription.rawValue
        viewModel.selectedSubcategory = PrivacyProFeedbackSubcategory.otp.rawValue

        await viewModel.process(action: .reportFAQClick)

        #expect(sender.submitScreenFAQClickPixelSent)
    }

    // MARK: - Source Tests

    @Test func testSource_PPro_SetsCorrectSource() {
        let viewModel = makeViewModel(source: .ppro)

        #expect(viewModel.source == "ppro")
    }

    @Test func testSource_DuckAi_SetsCorrectSource() {
        let viewModel = makeViewModel(source: .duckAi)

        #expect(viewModel.source == "duckAi")
    }

    @Test func testSource_VPN_SetsCorrectSource() {
        let viewModel = makeViewModel(source: .vpn)

        #expect(viewModel.source == "vpn")
    }

    @Test func testSource_Settings_SetsCorrectSource() {
        let viewModel = makeViewModel(source: .settings)

        #expect(viewModel.source == "settings")
    }

    // MARK: - Helper Functions

    /// Polls a condition until it's met or timeout is reached
    private func waitForCondition(
        timeout: TimeInterval = 2.0,
        pollingInterval: TimeInterval = 0.1,
        condition: @escaping () -> Bool
    ) async throws {
        let startTime = Date()

        while !condition() {
            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime >= timeout {
                throw TestError.generic // Timeout
            }

            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }
    }
}
