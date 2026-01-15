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

    let onConfirm: () -> Void
    let onViewSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(uiImage: DesignSystemImages.Color.Size128.contentUpload)

                VStack(spacing: 16) {
                    titleText
                    bodyText
                }

                VStack(spacing: 12) {
                    confirmButton
                    viewSettingsButton
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
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
                .frame(height: 50)
                .background(Color(designSystemColor: .buttonsPrimaryDefault))
                .cornerRadius(12)
        }
    }

    private var viewSettingsButton: some View {
        Button(action: onViewSettings) {
            Text(UserText.aiChatContextualOnboardingViewSettings)
                .daxButton()
                .foregroundColor(Color(designSystemColor: .accent))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    AIChatContextualOnboardingView(
        onConfirm: {},
        onViewSettings: {}
    )
}
#endif
