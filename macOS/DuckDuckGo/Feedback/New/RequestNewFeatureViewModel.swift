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
        selectedFeatures.contains("Incognito")
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
            "Advanced ad blocking",
            "AI support",
            "Cast video/audio",
            "Customize browser theme",
            "Dark mode on all sites",
            "Import bookmarks folders",
            "Import history",
            "Incognito",
            "Move browser buttons",
            "New tab page widgets",
            "Password manager extensions",
            "Picture-in-picture",
            "Reader mode",
            "Tab groups",
            "User profiles",
            "Vertical tabs",
            "Website translation"
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
