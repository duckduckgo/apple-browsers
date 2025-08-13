//
//  RequestNewFeatureViewModel.swift
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

import Combine
import SwiftUI
import BrowserServicesKit
import Common

// MARK: - Feature Model

struct FeedbackFeature: Identifiable, Hashable {
    let id: String      // Backend identifier (e.g., "advanced-ad-blocking")
    let text: String    // Localized display text

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FeedbackFeature, rhs: FeedbackFeature) -> Bool {
        lhs.id == rhs.id
    }
}

final class RequestNewFeatureViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedFeatures: Set<String> = []  // Now stores Feature IDs
    @Published var customFeatureText: String = ""

    // MARK: - Properties

    private let feedbackSender: FeedbackSenderImplementing
    let availableFeatures: [FeedbackFeature]

    // MARK: - Computed Properties

    var shouldEnableSubmit: Bool {
        !selectedFeatures.isEmpty || !customFeatureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowIncognitoInfo: Bool {
        selectedFeatures.contains("incognito")
    }

    var hasSelectedFeatures: Bool {
        !selectedFeatures.isEmpty
    }

    var hasCustomText: Bool {
        !customFeatureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initialization

    init(feedbackSender: FeedbackSenderImplementing = FeedbackSender()) {
        let allFeatures = [
            FeedbackFeature(id: "advanced-ad-blocking", text: UserText.featureAdvancedAdBlocking),
            FeedbackFeature(id: "ai-support", text: UserText.featureAISupport),
            FeedbackFeature(id: "cast-video-audio", text: UserText.featureCastVideo),
            FeedbackFeature(id: "customize-browser-theme", text: UserText.featureCustomizeTheme),
            FeedbackFeature(id: "dark-mode-on-all-sites", text: UserText.featureDarkModeAllSites),
            FeedbackFeature(id: "import-bookmarks-folders", text: UserText.featureImportBookmarkFolders),
            FeedbackFeature(id: "import-history", text: UserText.featureImportHistory),
            FeedbackFeature(id: "incognito", text: UserText.featureIncognito),
            FeedbackFeature(id: "move-browser-buttons", text: UserText.featureMoveBrowserButtons),
            FeedbackFeature(id: "new-tab-page-widgets", text: UserText.featureNewTabPageWidgets),
            FeedbackFeature(id: "password-manager-extensions", text: UserText.featurePasswordManagerExtensions),
            FeedbackFeature(id: "picture-in-picture", text: UserText.featurePictureInPicture),
            FeedbackFeature(id: "reader-mode", text: UserText.featureReaderMode),
            FeedbackFeature(id: "tab-groups", text: UserText.featureTabGroups),
            FeedbackFeature(id: "user-profiles", text: UserText.featureUserProfiles),
            FeedbackFeature(id: "vertical-tabs", text: UserText.featureVerticalTabs),
            FeedbackFeature(id: "website-translation", text: UserText.featureWebsiteTranslation)
        ]

        self.availableFeatures = Array(allFeatures.shuffled().prefix(12))
        self.feedbackSender = feedbackSender
    }

    // MARK: - Methods

    func toggleFeature(_ featureId: String) {
        if selectedFeatures.contains(featureId) {
            selectedFeatures.remove(featureId)
        } else {
            selectedFeatures.insert(featureId)
        }
    }

    func submitFeedback() {
        let feedback = Feedback.from(selectedPillIds: Array(selectedFeatures),
                                     text: customFeatureText,
                                     appVersion: AppVersion.shared.versionNumber,
                                     category: .featureRequest,
                                     problemCategory: nil)

         feedbackSender.sendFeedback(feedback)
    }
}
