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
import DesignResourcesKit
import DesignResourcesKitIcons

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
    static let buttonCornerRadius: CGFloat = 12
    static let primingImageName: String = "DuckPlayer-PrimingAnimation"
    static let imageWidth: CGFloat = 150
    static let imageHeight: CGFloat = 150
    static let closeImage = "xmark"
    static let closeButtonFont: CGFloat = 18
    static let closeButtonSize: CGFloat = 24
    static let closeButtonPadding: CGFloat = 8
    static let playButtonFontSize: CGFloat = 22
    static let playButtonCornerRadius: CGFloat = 16
    static let buttonIconSpacing: CGFloat = 8
    static let buttonTopPadding: CGFloat = 10
    static let phoneViewWidth: CGFloat = 68
    static let phoneViewHeight: CGFloat = 120
    static let phoneViewScaleEffect: CGFloat = 0.66
    static let phoneViewTopPadding: CGFloat = 10
    static let mainVStackSpacing: CGFloat = 15
    static let mainHStackSpacing: CGFloat = 30
    static let textVStackSpacing: CGFloat = 8
}

/// The welcome pill view that appears when a user first encounters DuckPlayer
struct DuckPlayerWelcomePillView: View {
    @ObservedObject var viewModel: DuckPlayerWelcomePillViewModel
    @State private var isAnimating: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Subviews

    private var playButton: some View {
        Image(uiImage: DesignSystemImages.Glyphs.Size20.videoPlaySolid)
            .foregroundColor(.white)
            .font(.system(size: Constants.playButtonFontSize, weight: .bold))
            .cornerRadius(Constants.playButtonCornerRadius)
            .accessibilityLabel("Play")
            .accessibilityHint("Plays the video in DuckPlayer")
    }

    private var mainActionButton: some View {
        Button(
            action: { viewModel.openInDuckPlayer() },
            label: {
                HStack(spacing: Constants.buttonIconSpacing) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size20.videoPlaySolid)
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
            .padding(.top, Constants.buttonTopPadding)
            .accessibilityLabel("Watch in DuckPlayer")
            .accessibilityHint("Opens the video in DuckPlayer for privacy protection")
            .accessibilityIdentifier("duckPlayerWelcomeButton")
    }
    
    private var closeButton: some View {
        Button(action: {
            viewModel.close()
        }) {
            Image(uiImage: DesignSystemImages.Glyphs.Size16.close)
                .font(.system(size: Constants.closeButtonFont))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .frame(width: Constants.closeButtonSize, height: Constants.closeButtonSize)
                .background(Color(designSystemColor: .backgroundSheets))
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Close")
        .accessibilityHint("Dismisses the DuckPlayer welcome message")
        .accessibilityIdentifier("duckPlayerWelcomeCloseButton")
    }

    private var phoneView: some View {
        LottieView(
            lottieFile: Constants.primingImageName,
            loopMode: .mode(.playOnce),
            isAnimating: $isAnimating
        )
        .frame(width: Constants.phoneViewWidth, height: Constants.phoneViewHeight)
        .background(Color.clear)
        .scaleEffect(Constants.phoneViewScaleEffect)
        .padding(.top, Constants.phoneViewTopPadding)
        .accessibilityLabel("DuckPlayer animation")
        .accessibilityHint("Animated illustration showing DuckPlayer functionality")
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Constants.mainVStackSpacing) {
                HStack(alignment: .center, spacing: Constants.mainHStackSpacing) {
                    phoneView

                    VStack(alignment: .leading, spacing: Constants.textVStackSpacing) {
                        Text(UserText.duckPlayerOptInWelcomeMessageTitle)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .daxTitle3()
                            .accessibilityAddTraits(.isHeader)

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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("duckPlayerWelcomePill")
            
            if viewModel.onClose != nil {
                VStack {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    .padding(.trailing, Constants.closeButtonPadding)
                    .padding(.top, Constants.closeButtonPadding)
                    Spacer()
                }
            }
        }
    }
}
