//
//  UnifiedFeedbackFormViewModel.swift
//  DuckDuckGo
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

import Combine
import SwiftUI
import Subscription
import BrowserServicesKit

final class UnifiedFeedbackFormViewModel: ObservableObject {
    private static let supportURL = URL(string: "https://duckduckgo.com/subscription-support")!
    enum Source: String {
        case settings
        case ppro
        case vpn
        case pir
        case itr
        case duckAi
        case unknown
    }

    enum ViewState {
        case feedbackPending
        case feedbackSending
        case feedbackSendingFailed
        case feedbackSent
        case feedbackCanceled

        var canSubmit: Bool {
            switch self {
            case .feedbackPending: return true
            case .feedbackSending: return false
            case .feedbackSendingFailed: return true
            case .feedbackSent: return false
            case .feedbackCanceled: return false
            }
        }
    }

    enum ViewAction {
        case submit
        case faqClick
        case reportShow
        case reportActions
        case reportCategory
        case reportSubcategory
        case reportFAQClick
        case reportSubmitShow
        case contactSupportClick
    }

    @Published var viewState: ViewState {
        didSet {
            updateSubmitButtonStatus()
        }
    }

    @Published var feedbackFormText: String = "" {
        didSet {
            updateSubmitButtonStatus()
        }
    }

    @Published private(set) var submitButtonEnabled: Bool = false
    @Published var selectedReportType: String? {
        didSet {
            selectedCategory = ""
        }
    }
    @Published var selectedCategory: String? {
        didSet {
            selectedSubcategory = ""
        }
    }
    @Published var selectedSubcategory: String? {
        didSet {
            feedbackFormText = ""
        }
    }

    var usesCompactForm: Bool {
        guard let selectedReportType else { return false }
        switch UnifiedFeedbackReportType(rawValue: selectedReportType) {
        case .reportIssue:
            return false
        default:
            return true
        }
    }

    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let vpnMetadataCollector: any UnifiedMetadataCollector
    private let dbpMetadataCollector: any UnifiedMetadataCollector
    private let defaultMetadataCollector: any UnifiedMetadataCollector
    private let feedbackSender: any UnifiedFeedbackSender
    private let isPaidAIChatFeatureEnabled: () -> Bool

    let source: String

    private(set) var availableCategories: [UnifiedFeedbackCategory] = [.subscription]

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         vpnMetadataCollector: any UnifiedMetadataCollector,
         dbpMetadataCollector: any UnifiedMetadataCollector,
         defaultMetadatCollector: any UnifiedMetadataCollector = DefaultMetadataCollector(),
         feedbackSender: any UnifiedFeedbackSender = DefaultFeedbackSender(),
         isPaidAIChatFeatureEnabled: @escaping () -> Bool,
         source: Source = .unknown) {
        self.viewState = .feedbackPending
        self.subscriptionManager = subscriptionManager
        self.vpnMetadataCollector = vpnMetadataCollector
        self.dbpMetadataCollector = dbpMetadataCollector
        self.defaultMetadataCollector = defaultMetadatCollector
        self.feedbackSender = feedbackSender
        self.isPaidAIChatFeatureEnabled = isPaidAIChatFeatureEnabled
        self.source = source.rawValue

        Task {
            // This requires follow-up work:
            // https://app.asana.com/1/137249556945/task/1210799126744217
            let features = (try? await subscriptionManager.currentSubscriptionFeatures()) ?? []

            if features.contains(.networkProtection) {
                availableCategories.append(.vpn)
            }
            if features.contains(.dataBrokerProtection) {
                availableCategories.append(.pir)
            }
            if features.contains(.paidAIChat) && isPaidAIChatFeatureEnabled() {
                availableCategories.append(.duckAi)
            }
            if features.contains(.identityTheftRestoration) || features.contains(.identityTheftRestorationGlobal) {
                availableCategories.append(.itr)
            }
        }
    }

    @MainActor
    func process(action: ViewAction) async {
        switch action {
        case .submit:
            self.viewState = .feedbackSending

            do {
                try await sendFeedback()
                self.viewState = .feedbackSent
            } catch {
                self.viewState = .feedbackSendingFailed
            }

            NotificationCenter.default.post(name: .unifiedFeedbackNotification, object: nil)
        case .faqClick:
            await openFAQ()
        case .reportShow:
            await feedbackSender.sendFormShowPixel()
        case .reportActions:
            await feedbackSender.sendActionsScreenShowPixel(source: source)
        case .reportCategory:
            if let selectedReportType {
                await feedbackSender.sendCategoryScreenShow(source: source,
                                                            reportType: selectedReportType)
            }
        case .reportSubcategory:
            if let selectedReportType, let selectedCategory {
                await feedbackSender.sendSubcategoryScreenShow(source: source,
                                                               reportType: selectedReportType,
                                                               category: selectedCategory)
            }
        case .reportFAQClick:
            if let selectedReportType, let selectedCategory, let selectedSubcategory {
                await feedbackSender.sendSubmitScreenFAQClickPixel(source: source,
                                                                   reportType: selectedReportType,
                                                                   category: selectedCategory,
                                                                   subcategory: selectedSubcategory)
            }
        case .reportSubmitShow:
            if let selectedReportType, let selectedCategory, let selectedSubcategory {
                await feedbackSender.sendSubmitScreenShowPixel(source: source,
                                                               reportType: selectedReportType,
                                                               category: selectedCategory,
                                                               subcategory: selectedSubcategory)
            }
        case .contactSupportClick:
            await openSupport()
        }
    }

    private func openFAQ() async {
        guard let selectedReportType, UnifiedFeedbackReportType(rawValue: selectedReportType) == .reportIssue,
              let selectedCategory, let category = UnifiedFeedbackCategory(rawValue: selectedCategory),
              let selectedSubcategory else {
            return
        }

        let url: URL? = {
        switch category {
            case .subscription: return SubscriptionFeedbackSubcategory(rawValue: selectedSubcategory)?.url
            case .vpn: return VPNFeedbackSubcategory(rawValue: selectedSubcategory)?.url
            case .pir: return PIRFeedbackSubcategory(rawValue: selectedSubcategory)?.url
            case .itr: return ITRFeedbackSubcategory(rawValue: selectedSubcategory)?.url
            case .duckAi: return PaidAIChatFeedbackSubcategory(rawValue: selectedSubcategory)?.url
            }
        }()

        if let url {
            await UIApplication.shared.open(url)
        }
    }

    private func sendFeedback() async throws {
        guard let selectedReportType else { return }
        switch UnifiedFeedbackReportType(rawValue: selectedReportType) {
        case nil:
            return
        case .requestFeature:
            try await feedbackSender.sendFeatureRequestPixel(description: feedbackFormText,
                                                             source: source)
        case .general:
            try await feedbackSender.sendGeneralFeedbackPixel(description: feedbackFormText,
                                                              source: source)
        case .reportIssue:
            try await reportProblem()
        }
    }

    private func reportProblem() async throws {
        guard let selectedCategory, let selectedSubcategory else { return }
        switch UnifiedFeedbackCategory(rawValue: selectedCategory) {
        case .vpn:
            let metadata = await vpnMetadataCollector.collectMetadata()
            try await feedbackSender.sendReportIssuePixel(source: source,
                                                          category: selectedCategory,
                                                          subcategory: selectedSubcategory,
                                                          description: feedbackFormText,
                                                          metadata: metadata as? VPNMetadata)
        case .pir:
            let metadata = await dbpMetadataCollector.collectMetadata()
            try await feedbackSender.sendReportIssuePixel(source: source,
                                                          category: selectedCategory,
                                                          subcategory: selectedSubcategory,
                                                          description: feedbackFormText,
                                                          metadata: metadata as? DBPFeedbackMetadata)
        default:
            let metadata = await defaultMetadataCollector.collectMetadata()
            try await feedbackSender.sendReportIssuePixel(source: source,
                                                          category: selectedCategory,
                                                          subcategory: selectedSubcategory,
                                                          description: feedbackFormText,
                                                          metadata: metadata as? DefaultFeedbackMetadata)
        }
    }


    private func updateSubmitButtonStatus() {
        self.submitButtonEnabled = viewState.canSubmit && !feedbackFormText.isEmpty
    }

    private func openSupport() {
        UIApplication.shared.open(Self.supportURL)
    }
}
