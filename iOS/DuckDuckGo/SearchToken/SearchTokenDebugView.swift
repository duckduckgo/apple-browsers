//
//  SearchTokenDebugView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Core
import PrivacyConfig
import SwiftUI

/// Debug screen for the Search Token (Dindex) experiment.
///
/// Only the fetcher-independent controls are implemented here: the experiment cohort override (reusing the
/// Feature Flags view), the base-URL override, and a placeholder for the future WebView-cookie bridge. The
/// cached-token display and the Fetch/Clear actions need a live `SearchTokenFetcher` instance and are pending
/// the ownership decision.
struct SearchTokenDebugView: View {

    @State private var baseURLOverride: String = URL.searchTokenURLOverride ?? ""

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExperimentCohortView(viewModel: FeatureFlagsSettingViewModel(),
                                         experiment: FeatureFlag.searchTokenExperiment)
                } label: {
                    Text(verbatim: "Experiment cohort override")
                }
            }

            Section {
                TextField("Custom search-token URL", text: $baseURLOverride)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    let trimmed = baseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
                    URL.searchTokenURLOverride = trimmed.isEmpty ? nil : trimmed
                    baseURLOverride = URL.searchTokenURLOverride ?? ""
                } label: {
                    Text(verbatim: "Save")
                }
                Button(role: .destructive) {
                    URL.searchTokenURLOverride = nil
                    baseURLOverride = ""
                } label: {
                    Text(verbatim: "Reset to default")
                }
            } header: {
                Text(verbatim: "Base URL")
            } footer: {
                Text(verbatim: "Overrides SEARCH_TOKEN_URL. Empty = default. Effective URL: \(URL.searchToken.absoluteString). Applies to fetchers created after the change.")
            }

        }
        .navigationTitle(Text(verbatim: "Search Token"))
    }
}
