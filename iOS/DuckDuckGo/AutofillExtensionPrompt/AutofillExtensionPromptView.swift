//
//  AutofillExtensionPromptView.swift
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

import SwiftUI

struct AutofillExtensionPromptView: View {

    @State var frame: CGSize = .zero
    @ObservedObject var viewModel: AutofillExtensionPromptViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            makeBodyView(geometry)
        }
    }

    private func makeBodyView(_ geometry: GeometryProxy) -> some View {
        DispatchQueue.main.async { self.frame = geometry.size }

        return ZStack {
            AutofillViews.CloseButtonHeader(action: viewModel.dismissButtonPressed)
                .offset(x: horizontalPadding)
                .zIndex(1)

            VStack {
                AnimationView(isAnimating: $isAnimating)
                AutofillViews.Headline(title: UserText.extensionPromotionTitle)
                Spacer()
                    .frame(height: Const.Size.headlineTopPadding)
                AutofillViews.Description(text: UserText.extensionPromotionMessage)
                contentViewSpacer
                ctaView
                    .padding(.bottom, AutofillViews.isIPad(verticalSizeClass, horizontalSizeClass) ? Const.Size.bottomPaddingIPad
                             : Const.Size.bottomPadding)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAnimating = true
                }
            }
            .background(GeometryReader { proxy -> Color in
                // Using main dispatch queue to avoid SwiftUI geometry updates conflicts
                // since modifying view state during geometry calculation can cause issues
                DispatchQueue.main.async { viewModel.contentHeight = proxy.size.height }
                return Color.clear
            })
            .useScrollView(shouldUseScrollView(), minHeight: frame.height)

        }
        .padding(.horizontal, horizontalPadding)

    }

    private func shouldUseScrollView() -> Bool {
        AutofillViews.contentHeightExceedsScreenHeight(viewModel.contentHeight)
    }

    private struct AnimationView: View {
        @Binding var isAnimating: Bool
        @Environment(\.colorScheme) private var colorScheme

        private var lottieFileName: String {
            colorScheme == .dark ? "autofill-extension-dark" : "autofill-extension-light"
        }

        var body: some View {
            LottieView(
                lottieFile: lottieFileName,
                loopMode: .mode(.loop),
                isAnimating: $isAnimating
            )
            .frame(width: Const.Size.animationWidth)
            .aspectRatio(contentMode: .fit)
        }
    }

    private var contentViewSpacer: some View {
        VStack {
            if AutofillViews.isIPhoneLandscape(verticalSizeClass) {
                AutofillViews.LegacySpacerView(height: Const.Size.contentSpacerHeightLandscape)
            } else {
                AutofillViews.LegacySpacerView(height: Const.Size.contentSpacerHeight)
            }
        }
    }

    private var ctaView: some View {
        VStack(spacing: Const.Size.ctaVerticalSpacing) {
            AutofillViews.PrimaryButton(title: UserText.extensionPromotionButtonTitle,
                                        action: viewModel.enableExtensionPressed)

            AutofillViews.TertiaryButton(title: UserText.extensionPromotionButtonDismissTitle,
                                         action: viewModel.setUpLaterButtonPressed)
        }
    }

    private var horizontalPadding: CGFloat {
        if AutofillViews.isIPhonePortrait(verticalSizeClass, horizontalSizeClass) {
            if AutofillViews.isSmallFrame(frame) {
                return Const.Size.closeButtonOffsetPortraitSmallFrame
            } else {
                return Const.Size.closeButtonOffsetPortrait
            }
        } else {
            return Const.Size.closeButtonOffset
        }
    }
}

// MARK: - Constants

private enum Const {
    enum Size {
        static let closeButtonOffset: CGFloat = 48.0
        static let closeButtonOffsetPortrait: CGFloat = 44.0
        static let closeButtonOffsetPortraitSmallFrame: CGFloat = 16.0
        static let headlineTopPadding: CGFloat = 16.0
        static let contentSpacerHeight: CGFloat = 24.0
        static let contentSpacerHeightLandscape: CGFloat = 30.0
        static let ctaVerticalSpacing: CGFloat = 8.0
        static let bottomPadding: CGFloat = 12.0
        static let bottomPaddingIPad: CGFloat = 24.0
        static let animationWidth: CGFloat = 300.0
    }
}
