//
//  AIChatContextualOnboardingView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

struct AIChatContextualOnboardingView: View {

    private enum Constants {
        static let contentSpacing: CGFloat = 24
        static let textSpacing: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let buttonTopPadding: CGFloat = 8
        static let horizontalPadding: CGFloat = 20
        static let buttonHeight: CGFloat = 50
        static let buttonCornerRadius: CGFloat = 12
        static let heroImageTopPadding: CGFloat = 25

    }

    let onConfirm: () -> Void
    let onViewSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Constants.contentSpacing) {
                Image(uiImage: DesignSystemImages.Color.Size128.contentUpload)
                    .padding(.top, Constants.heroImageTopPadding)

                VStack(spacing: Constants.textSpacing) {
                    titleText
                    bodyText
                }

                VStack(spacing: Constants.buttonSpacing) {
                    confirmButton
                    viewSettingsButton
                }
                .padding(.top, Constants.buttonTopPadding)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(designSystemColor: .backgroundTertiary))
    }

    private var titleText: some View {
        Text(UserText.aiChatContextualOnboardingTitle)
            .daxTitle1()
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .multilineTextAlignment(.center)
    }

    private var bodyText: some View {
        Text(UserText.aiChatContextualOnboardingBody)
            .daxBodyRegular()
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var confirmButton: some View {
        Button(action: onConfirm) {
            Text(UserText.aiChatContextualOnboardingGotIt)
                .daxButton()
                .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                .frame(maxWidth: .infinity)
                .frame(height: Constants.buttonHeight)
                .background(Color(designSystemColor: .buttonsPrimaryDefault))
                .cornerRadius(Constants.buttonCornerRadius)
        }
    }

    private var viewSettingsButton: some View {
        Button(action: onViewSettings) {
            Text(UserText.aiChatContextualOnboardingViewSettings)
                .daxButton()
                .foregroundColor(Color(designSystemColor: .accent))
                .frame(maxWidth: .infinity)
                .frame(height: Constants.buttonHeight)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    AIChatContextualOnboardingView(
        onConfirm: {},
        onViewSettings: {}
    )
}
