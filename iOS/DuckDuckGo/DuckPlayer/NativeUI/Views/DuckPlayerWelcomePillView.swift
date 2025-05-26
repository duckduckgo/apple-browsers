//
//  DuckPlayerWelcomePillView.swift
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

import Foundation
import SwiftUI
import Combine

/// Constants used in DuckPlayerWelcomePillView
private struct Constants {
    static let vStackSpacing: CGFloat = 16
    static let hStackSpacing: CGFloat = 20
    static let daxLogo = "DaxLogoSimple"
    static let iconSize: CGFloat = 40
    static let horizontalPadding: CGFloat = 32
    static let verticalPadding: CGFloat = 24
    static let cornerRadius: CGFloat = 12
    static let shadowOpacity: CGFloat = 0.1
    static let shadowRadius: CGFloat = 3
    static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
    static let mainButtonHeight: CGFloat = 40
    static let buttonCornerRadius: CGFloat = 8
    static let primingImageName: String = "DuckPlayer-PrimingAnimation"
    static let imageWidth: CGFloat = 150
    static let imageHeight: CGFloat = 150
}

/// The welcome pill view that appears when a user first encounters DuckPlayer
struct DuckPlayerWelcomePillView: View {
    @ObservedObject var viewModel: DuckPlayerWelcomePillViewModel

    // Add state to track the height
    @State private var viewHeight: CGFloat = 100
    @State private var iconSize: CGFloat = 40

    @State private var isAnimating: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var playButton: some View {
        Image(systemName: "play.fill")
            .foregroundColor(.white)
            .font(.system(size: 22, weight: .bold))
            .cornerRadius(16)
    }

    private var mainActionButton: some View {
        Button(
            action: { viewModel.openInDuckPlayer() },
            label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                    Text(UserText.duckPlayerOptInPillTitle)
                        .daxButton()
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Constants.mainButtonHeight)
                 .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                .background(Color(designSystemColor: .buttonsPrimaryDefault))
                .cornerRadius(Constants.buttonCornerRadius)
            })
            .padding(.top, 10)
    }

    private var phoneView: some View {
        LottieView(
            lottieFile: Constants.primingImageName,
            loopMode: .mode(.playOnce),
            isAnimating: $isAnimating
        )
        .frame(width: 68, height: 120)
        .background(Color.clear)
        .scaleEffect(0.66)
        .padding(.top, 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 30) {
                phoneView

                VStack(alignment: .leading, spacing: 8) {
                    Text(UserText.duckPlayerOptInWelcomeMessageTitle)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .daxTitle3()

                    Text(UserText.duckPlayerOptInWelcomeMessageContent)
                        .font(.subheadline)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .daxBodyRegular()
                }
            }
            mainActionButton
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(
            Color(designSystemColor: colorScheme == .dark ? .container : .backgroundSheets)
        )
        .cornerRadius(Constants.cornerRadius)
        .shadow(
            color: Color.black.opacity(Constants.shadowOpacity),
            radius: Constants.shadowRadius,
            x: Constants.shadowOffset.width,
            y: Constants.shadowOffset.height
        )
    }
}
