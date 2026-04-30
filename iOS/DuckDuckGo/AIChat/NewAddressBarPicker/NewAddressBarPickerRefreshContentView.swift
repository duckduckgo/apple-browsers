//
//  NewAddressBarPickerRefreshContentView.swift
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

import SwiftUI
import UIComponents
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import AIChat
import Core
import Onboarding

struct NewAddressBarPickerRefreshContentView: View {
    @ObservedObject var viewModel: NewAddressBarPickerViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(designSystemColor: .background)
                .ignoresSafeArea()

            BackgroundIllustration()

            VStack(spacing: 24) {
                Header()
                PickerCard(viewModel: viewModel)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 440)
            .padding(.top, 24)
            .padding(.horizontal, 16)
        }
    }
}

private struct Header: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: DesignSystemImages.Color.Size32.duckDuckGo)
                .resizable()
                .frame(width: 32, height: 32)

            HStack(spacing: 8) {
                BadgeView(text: UserText.settingsItemNewBadge)
                Text(UserText.newAddressBarPickerTitle)
                    .textCase(.uppercase)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
        }
    }
}

private struct PickerCard: View {
    @ObservedObject var viewModel: NewAddressBarPickerViewModel
    @Environment(\.onboardingTheme) private var onboardingTheme

    var body: some View {
        VStack(spacing: 20) {
            Text(UserText.newAddressBarPickerRefreshHeadline)
                .daxTitle2()
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SettingsAIExperimentalPickerView(isDuckAISelected: $viewModel.isDuckAISelected)

            Text(UserText.newAddressBarPickerRefreshFooter)
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.confirm()
            } label: {
                Text(UserText.newAddressBarPickerConfirm)
            }
            .buttonStyle(onboardingTheme.primaryButtonStyle.style)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(designSystemColor: .surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(designSystemColor: .accent).opacity(0.3), lineWidth: 1)
        )
    }
}

private struct BackgroundIllustration: View {
    var body: some View {
        VStack {
            Spacer()
            Image("ab-picker-background")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: [.bottom, .leading, .trailing])
    }
}
