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

    static let targetWidth: CGFloat = 504
    static let height: CGFloat = 273
    static let totalHeight: CGFloat = height + 2 * Const.verticalPadding

    enum Const {
        static let verticalPadding = 40.0
        static let searchBoxVerticalSpacing = 24.0
        static let promoTopPadding = 24.0
    }

    @ObservedObject var promoViewModel: SubscriptionPromoViewModel
    @State private var promoCardHeight: CGFloat = 0

    @EnvironmentObject var model: AppearancePreferences
    @EnvironmentObject var themeManager: ThemeManager

    private var backgroundColor: Color {
        Color(designSystemColor: .surfaceCanvas, palette: themeManager.designColorPalette)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        if promoViewModel.shouldShowPromo {
                            SubscriptionPromoView(
                                actionType: .learnMore,
                                promoCardWidth: Self.targetWidth,
                                onButtonTap: { promoViewModel.onPromoButtonTapped() },
                                onClose: { promoViewModel.dismiss() }
                            )
                            .padding(.top, Const.promoTopPadding)
                            .readSize { promoCardHeight = $0.height }
                        }

                        VStack(spacing: Const.searchBoxVerticalSpacing) {
                            Spacer(minLength: Const.verticalPadding)

                            Group {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.homeFavoritesGhost, style: StrokeStyle(lineWidth: 1.0))
                                        .background(Color(designSystemColor: .surfaceTertiary))
                                        .cornerRadius(12)

                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack {
                                            Image(.updatedBurnerWindowHome)
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
                                .frame(height: Self.height)
                            }
                            .frame(width: Self.targetWidth)

                            Spacer(minLength: Const.verticalPadding)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(geometry.size.height - (promoViewModel.shouldShowPromo ? promoCardHeight : 0), Self.totalHeight))
                    }
                }
            }
            .background(backgroundColor)
        }
    }
}

struct FeaturesBox: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(.burnerWindowIcon1)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(UserText.burnerHomepageDescription1)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

            }

            HStack {
                Image(.burnerWindowIcon2)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(UserText.burnerHomepageDescription2)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }

            HStack {
                Image(.burnerWindowIcon3)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(UserText.burnerHomepageDescription3)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }

            Divider()

            HStack {
                Image(.burnerWindowIcon4)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .opacity(0.6)
                    .padding(.top, -20)
                Text(UserText.burnerHomepageDescription4)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
        }
    }
}
