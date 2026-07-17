//
//  BurnerHomePageView.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Foundation
import SwiftUI

struct BurnerHomePageView: View {

    static let targetWidth: CGFloat = 508
    static let height: CGFloat = 273

    enum Const {
        static let verticalPadding = 40.0
        static let contentGap = 20.0
    }

    @ObservedObject var promoViewModel: SubscriptionPromoViewModel

    @EnvironmentObject var model: AppearancePreferences
    @EnvironmentObject var themeManager: ThemeManager

    private var backgroundColor: Color {
        Color(designSystemColor: .surfaceCanvas, palette: themeManager.designColorPalette)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Const.contentGap) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.homeFavoritesGhost, style: StrokeStyle(lineWidth: 1.0))
                            .background(Color(designSystemColor: .surfaceTertiary))
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(themeManager.isAppRebranded ? .updatedBurnerWindowHome : .updatedBurnerWindowHomeLegacy)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64, height: 48)
                                    .padding(.leading, -15)
                                    .padding(.top, -5)

                                Text(UserText.burnerWindowHeader)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(Color(designSystemColor: .textPrimary))
                                    .padding(.leading, -6)
                            }

                            FeaturesBox()
                                .padding(.top, 10)
                        }
                        .padding(.horizontal, 40)
                    }
                    .frame(width: Self.targetWidth, height: Self.height)

                    if promoViewModel.shouldShowPromo {
                        SubscriptionPromoView(
                            actionType: promoViewModel.isEligibleForFreeTrial ? .tryForFree : .learnMore,
                            promoCardWidth: Self.targetWidth,
                            onButtonTap: { promoViewModel.onPromoButtonTapped() },
                            onClose: { promoViewModel.dismiss() }
                        )
                    }
                }
                .padding(.vertical, Const.verticalPadding)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .background(backgroundColor)
        }
    }
}

struct FeaturesBox: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureRow(icon: .burnerWindowIcon1, text: UserText.burnerHomepageDescription1)
            FeatureRow(icon: .burnerWindowIcon2, text: UserText.burnerHomepageDescription2)
            FeatureRow(icon: .burnerWindowIcon3, text: UserText.burnerHomepageDescription3)

            Divider()

            FeatureRow(icon: .burnerWindowIcon4, text: UserText.burnerHomepageDescription4, iconOpacity: 0.6, iconTopPadding: -20)
        }
    }

    private struct FeatureRow: View {
        let icon: ImageResource
        let text: String
        var iconOpacity: Double = 1.0
        var iconTopPadding: CGFloat = 0

        var body: some View {
            HStack {
                Image(icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .opacity(iconOpacity)
                    .padding(.top, iconTopPadding)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
        }
    }
}
