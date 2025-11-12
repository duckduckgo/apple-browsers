//
//  AutofillExtensionPromotionHeaderView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import Lottie

struct AutofillExtensionPromotionHeaderView: View {
    var primaryButtonAction: (() -> Void)?
    var dismissButtonAction: (() -> Void)?

    @State private var isAnimating = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                AnimationView(isAnimating: $isAnimating)

                Text(UserText.extensionPromotionTitle)
                    .daxTitle3()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Button {
                    primaryButtonAction?()
                } label: {
                    HStack {
                        Text(UserText.extensionPromotionButtonTitle)
                            .daxButton()
                    }
                }
                .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: false))
                .frame(maxWidth: 360)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Button {
                dismissButtonAction?()
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .foregroundColor(.primary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(.trailing, 4)
            .padding(.top, 4)
            .accessibilityIdentifier("Button_DismissExtensionPromo")
        }
        .background(
            RoundedRectangle(cornerRadius: 24.0)
                .foregroundColor(Color(designSystemColor: .surface))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)
        )
        .onAppear {
            isAnimating = true
        }
        .padding(.horizontal, 20)
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
            .frame(width: 320)
            .aspectRatio(contentMode: .fit)
        }
    }
}

#Preview {
    AutofillExtensionPromotionHeaderView()
}
