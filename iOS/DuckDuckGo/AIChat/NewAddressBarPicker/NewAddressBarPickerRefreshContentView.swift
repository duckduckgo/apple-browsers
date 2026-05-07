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
import Onboarding

struct NewAddressBarPickerRefreshContentView: View {
    @StateObject var viewModel: NewAddressBarPickerViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.stackSpacing) {
                Header()
                PickerCard(viewModel: viewModel)
            }
            .frame(maxWidth: cardMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.topPadding)
            .padding(.horizontal, Metrics.horizontalPadding)
        }
        .background(BackgroundIllustration())
        .modifier(ScrollBounceBehaviorModifier())
    }

    private var cardMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? Metrics.cardMaxWidthPad : Metrics.cardMaxWidth
    }

    private enum Metrics {
        static let cardMaxWidth: CGFloat = 360
        static let cardMaxWidthPad: CGFloat = 420
        static let stackSpacing: CGFloat = 24
        static let topPadding: CGFloat = 24
        static let horizontalPadding: CGFloat = 16
    }
}

private struct Header: View {
    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Image(uiImage: DesignSystemImages.Color.Size32.duckDuckAI)

            HStack(spacing: Metrics.badgeSpacing) {
                BadgeView(text: UserText.settingsItemNewBadge)
                    .clipShape(Capsule())

                Text(UserText.newAddressBarPickerTitle)
                    .textCase(.uppercase)
                    .daxFootnoteSemibold()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
        }
    }

    private enum Metrics {
        static let spacing: CGFloat = 12
        static let badgeSpacing: CGFloat = 8
    }
}

private struct PickerCard: View {
    @ObservedObject var viewModel: NewAddressBarPickerViewModel
    @Environment(\.onboardingTheme) private var onboardingTheme

    var body: some View {
        VStack(spacing: Metrics.padding) {
            Text(UserText.newAddressBarPickerRefreshHeadline)
                .daxTitle2()
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            RebrandedOnboardingView.OnboardingSearchExperiencePicker(isDuckAISelected: $viewModel.isDuckAISelected)

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
        .padding(Metrics.padding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .fill(Color(designSystemColor: .surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .strokeBorder(Color(designSystemColor: .accent).opacity(Metrics.borderOpacity), lineWidth: 1)
        )
    }

    private enum Metrics {
        static let padding: CGFloat = 20
        static let cornerRadius: CGFloat = 16
        static let borderOpacity: CGFloat = 0.3
    }
}

private struct BackgroundIllustration: View {

    var body: some View {
        VStack {
            Spacer()
            OnboardingRebrandingImages.Linear.addressBarSearchPreferenceBackground
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxHeight: Metrics.backgroundMaxHeight)
        }
        .ignoresSafeArea()
    }

    private enum Metrics {
        static let backgroundMaxHeight: CGFloat = 294
    }
}
