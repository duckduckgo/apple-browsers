//
//  PreferencesPersonalInformationRemovalView.swift
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

import PreferencesUI_macOS
import SwiftUI
import SwiftUIExtensions

public struct PreferencesPersonalInformationRemovalView: View {

    @ObservedObject var model: PreferencesPersonalInformationRemovalModel

    public init(model: PreferencesPersonalInformationRemovalModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                TextMenuTitle(UserText.preferencesPersonalInformationRemovalTitle)

                StatusIndicatorView(status: model.status, isLarge: true)
            }

            openFeatureSection
            helpSection
        }
        .onAppear(perform: {
            model.didAppear()
        })
    }

    @ViewBuilder
    private var openFeatureSection: some View {
        PreferencePaneSection {
            Button(UserText.openPersonalInformationRemovalButton) { model.openPersonalInformationRemoval() }
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var helpSection: some View {
        PreferencePaneSection {
            TextMenuItemHeader(UserText.preferencesSubscriptionFooterTitle, bottomPadding: 0)

            TextMenuItemCaption(UserText.preferencesSubscriptionHelpFooterCaption)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                TextButton(UserText.viewFaqsButton, weight: .semibold) { model.openFAQ() }
            }
        }
    }
}
