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
import PrivacyConfig
import Combine
import Persistence

struct SERPSettingsView: View {

    /// Used to show the right settings screen on SERP
    let page: Page
    let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    let keyValueStore: ThrowingKeyValueStoring

    var body: some View {
        SERPSettingsWebView(url: page.url,
                            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
                            keyValueStore: keyValueStore)
            .ignoresSafeArea(edges: .bottom)
            .background()
    }

    enum Page {

        case general
        case searchAssist
        case hideAIGeneratedImages

        var url: URL {
            return switch self {
            case .searchAssist:
                URL.embeddedSearchAssistSettings
            case .hideAIGeneratedImages:
                URL.embeddedHideAIGeneratedImagesSettings
            default:
                URL.embeddedGeneralSERPSettings
            }
        }

    }

}
