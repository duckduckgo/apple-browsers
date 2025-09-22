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

    var body: some View {
        let isAIFeaturesEnabled = viewModel.isAIChatEnabled
        let hasSubscription = viewModel.isPaidAIChatAvailable
        let shouldShowAsOn = hasSubscription && isAIFeaturesEnabled
        
        let currentDescription = SettingsDescription(imageName: "AIChat-Settings",
                                                    title: UserText.aiChatSubscriptionTitle,
                                                    status: shouldShowAsOn ? .on : .off,
                                                    explanation: UserText.aiChatSubscriptionCaption)

        List {
            SettingsDescriptionView(content: currentDescription)
            if isAIFeaturesEnabled {
                Section(footer: Text(UserText.aiChatSubscriptionDisableAI)) {
                    SettingsCellView(label: UserText.openSubscriptionAIChat, action: {
                        viewModel.openAIChat()
                    }, webLinkIndicator: true, isButton: true
                    )
                }
            } else {
                Section {
                    VStack {
                        Text(UserText.aiChatSubscriptionEnableAI)
                            .foregroundStyle(.red)
                            .font(
                                Font(uiFont: UIFont.daxSubheadSemibold())
                            )
                    }
                    .listRowInsets(EdgeInsets(top: -12, leading: -12, bottom: -12, trailing: -12))
                    .listRowBackground(Color(designSystemColor: .background).edgesIgnoringSafeArea(.all))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .applySettingsListModifiers(title: UserText.aiChatSubscriptionTitle,
                                    displayMode: .inline,
                                    viewModel: viewModel)
    }

}
