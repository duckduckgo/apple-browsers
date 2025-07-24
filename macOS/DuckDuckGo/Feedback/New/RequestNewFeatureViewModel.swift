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

final class RequestNewFeatureViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedFeatures: Set<String> = []
    @Published var customFeatureText: String = ""

    // MARK: - Properties

    let availableFeatures: [String]

    // MARK: - Computed Properties

    var shouldEnableSubmit: Bool {
        !selectedFeatures.isEmpty || !customFeatureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowIncognitoInfo: Bool {
        selectedFeatures.contains(UserText.featureIncognito)
    }

    var hasSelectedFeatures: Bool {
        !selectedFeatures.isEmpty
    }

    var hasCustomText: Bool {
        !customFeatureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initialization

    init() {
        let allFeatures = [
            UserText.featureAdvancedAdBlocking,
            UserText.featureAISupport,
            UserText.featureCastVideo,
            UserText.featureCustomizeTheme,
            UserText.featureDarkModeAllSites,
            UserText.featureImportBookmarkFolders,
            UserText.featureImportHistory,
            UserText.featureIncognito,
            UserText.featureMoveBrowserButtons,
            UserText.featureNewTabPageWidgets,
            UserText.featurePasswordManagerExtensions,
            UserText.featurePictureInPicture,
            UserText.featureReaderMode,
            UserText.featureTabGroups,
            UserText.featureUserProfiles,
            UserText.featureVerticalTabs,
            UserText.featureWebsiteTranslation
        ]

        self.availableFeatures = Array(allFeatures.shuffled().prefix(12))
    }

    // MARK: - Methods

    func toggleFeature(_ feature: String) {
        if selectedFeatures.contains(feature) {
            selectedFeatures.remove(feature)
        } else {
            selectedFeatures.insert(feature)
        }
    }

    func submitFeedback() {
        // Future implementation for submitting feedback
    }
}
