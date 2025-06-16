//
//  SubscriptionAIChatView.swift
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

struct SubscriptionAIChatView: View {

    let viewModel: SettingsViewModel

    private var description: PreferencesDescription {
        PreferencesDescription(imageName: "AIChat-Settings",
                                     title: UserText.aiChatSubscriptionTitle,
                                     status: viewModel.isPaidAIChatAvailable ? .on : .off,
                                     explanation: UserText.aiChatSubscriptionCaption)
    }

    var body: some View {
        List {
            PreferencesDescriptionView(content: description)
            Section {
                SettingsCellView(label: UserText.openSubscriptionAIChat, action: {
                    viewModel.openAIChat()
                }, webLinkIndicator: true, isButton: true
                )
            }
        }
        .applySettingsListModifiers(title: UserText.aiChatSubscriptionTitle,
                                     displayMode: .inline,
                                     viewModel: viewModel)
    }
}
