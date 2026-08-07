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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Metrics.stackSpacing) {
                    Header()
                    PickerCard(viewModel: viewModel)
                        .id(Metrics.pickerCardID)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: cardMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, Metrics.topPadding)
                .padding(.horizontal, Metrics.horizontalPadding)
            }
            .background(BackgroundIllustration())
            .modifier(ScrollBounceBehaviorModifier())
            .onAppear {
                centerPickerCardIfNeeded(proxy: proxy)
            }
            .onChange(of: verticalSizeClass) { newVerticalSizeClass in
                centerPickerCardIfNeeded(proxy: proxy, newVerticalSizeClass: newVerticalSizeClass)
            }
        }
        .ignoresSafeArea(.container, edges: isVerticallyCompact() ? .vertical : [])
    }

    private func centerPickerCardIfNeeded(proxy: ScrollViewProxy, newVerticalSizeClass: UserInterfaceSizeClass? = nil) {
        guard isVerticallyCompact(newVerticalSizeClass: newVerticalSizeClass) else {
            return
        }

        proxy.scrollTo(Metrics.pickerCardID, anchor: .center)
    }

    private func isVerticallyCompact(newVerticalSizeClass: UserInterfaceSizeClass? = nil) -> Bool {
        let targetClass = newVerticalSizeClass ?? verticalSizeClass
        return targetClass == .compact
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
        static let pickerCardID = "pickerCard"
    }
}

private struct Header: View {
    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Image(uiImage: DesignSystemImages.Color.Size32.duckDuckAI)

            Text(UserText.newAddressBarPickerTitle)
                .textCase(.uppercase)
                .daxFootnoteSemibold()
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
    }

    private enum Metrics {
        static let spacing: CGFloat = 12
    }
}

private struct PickerCard: View {
    @ObservedObject var viewModel: NewAddressBarPickerViewModel
    @Environment(\.onboardingTheme) private var onboardingTheme

    var body: some View {
        OnboardingBubbleView(tailPosition: nil) {
            VStack(spacing: Metrics.spacing) {
                Text(UserText.newAddressBarPickerRefreshHeadline)
                    .daxTitle2()
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                OnboardingView.OnboardingSearchExperiencePicker(isDuckAISelected: $viewModel.isDuckAISelected)

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
        }
    }

    private enum Metrics {
        static let spacing: CGFloat = 20
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
