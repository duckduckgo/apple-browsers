//
//  SERPSettingsView.swift
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


import Core
import SwiftUI
import DesignResourcesKit

struct SERPSettingsView: View {

    enum SERPSettingsPage: String {

        case main
        case aiFeatures

    }

    /// Used to show the right settings screen on SERP, e.g. pass aifeatures
    let page: SERPSettingsPage
    let webViewModel = AsyncHeadlessWebViewViewModel(settings: AsyncHeadlessWebViewSettings())

    var settingsURL: URL {
        let url = switch page {
        case .aiFeatures:
            URL.directAIFeaturesSettings.appendingParameter(
                name: SERPSettingsConstants.returnParameterKey,
                value: SERPSettingsConstants.aiFeatures)
        default:
            URL.directSearchSettings.appendingParameter(
                name: SERPSettingsConstants.returnParameterKey,
                value: SERPSettingsConstants.privateSearch)
        }
        return url.appendingParameter(name: "embedded", value: "1")
    }

    var body: some View {
        AsyncHeadlessWebView(viewModel: webViewModel)
            .background()
            .onAppear {
                webViewModel.navigationCoordinator.navigateTo(url: settingsURL)
            }
    }

}
