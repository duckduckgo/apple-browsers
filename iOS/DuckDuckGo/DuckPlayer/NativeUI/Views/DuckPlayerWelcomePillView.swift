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
    static let regularPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 16
    static let shadowOpacity: CGFloat = 0.1
    static let shadowRadius: CGFloat = 3
    static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
    static let mainButtonHeight: CGFloat = 50
    static let buttonCornerRadius: CGFloat = 14
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
            .font(.system(size: 20, weight: .bold))
            .frame(width: 100, height: 300)
            .cornerRadius(16)
    }

    private var mainActionButton: some View {
        Button(
            action: { viewModel.openInDuckPlayer() },
            label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                    Text(verbatim: "Play this video in Duck Player")
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Constants.mainButtonHeight)
                 .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                .background(Color(designSystemColor: .buttonsPrimaryDefault))
                .cornerRadius(Constants.buttonCornerRadius)
                .padding(.horizontal, Constants.regularPadding)
                .padding(.bottom, Constants.regularPadding)
            })
            .padding(.top, 22)
    }

    private var phoneView: some View {
        LottieView(
            lottieFile: Constants.primingImageName,
            loopMode: .mode(.playOnce),
            isAnimating: $isAnimating
        )
        .frame(width: 70, height: 120)
        .background(Color.clear)
        .scaleEffect(0.7)
        .padding(.top, 10)
        .padding(.leading, 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 20) {
                phoneView

                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "YouTube, but with fewer ads, and more privacy.")
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .daxTitle3()

                    Text(verbatim: "Duck Player blocks targeted ads and keeps your history private.")
                        .font(.subheadline)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .daxBodyRegular()
                }
            }
            .padding(.horizontal, Constants.regularPadding)
            .padding(.top, Constants.regularPadding)

            mainActionButton
        }
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
