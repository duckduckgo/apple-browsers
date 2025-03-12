//
//  DuckPlayerView.swift
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
import Foundation
import DesignResourcesKit

struct DuckPlayerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var viewModel: DuckPlayerViewModel
    var webView: DuckPlayerWebView

    enum Constants {
        static let headerHeight: CGFloat = 56
        static let iconSize: CGFloat = 32
        static let cornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 16
        static let videoAspectRatio: CGFloat = 9/16 // 16:9 in portrait
        static let daxLogoSize: CGFloat = 24.0
        static let daxLogo = "Home"
        static let duckPlayerImage: String = "DuckPlayer"
        static let duckPlayerSettingsImage: String = "DuckPlayerOpenSettings"
        static let duckPlayerYoutubeImage: String = "OpenInYoutube"
        static let bottomButtonHeight: CGFloat = 44
        static let grabHandleHeight: CGFloat = 4
        static let grabHandleWidth: CGFloat = 36
    }

    var body: some View {
        ZStack {
            // Background with blur effect
            Color(.black)
            .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Grab Handle
                if !viewModel.isLandscape {
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: Constants.grabHandleWidth, height: Constants.grabHandleHeight)
                        .padding(.top, 8)
                }

                // Header
                if !viewModel.isLandscape {
                    header
                        .frame(height: Constants.headerHeight)
                }

                // Video Container
                Spacer()
                GeometryReader { geometry in
                    ZStack {
                        webView
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.width * Constants.videoAspectRatio
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                }

                if viewModel.shouldShowYouTubeButton {
                    HStack(spacing: 8) {
                        Button {
                            viewModel.openInYouTube()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                HStack(spacing: 8) {
                                    Image(Constants.duckPlayerYoutubeImage)
                                        .renderingMode(.template)
                                        .foregroundColor(.white)
                                        .frame(width: 24, height: 24)
                                    Text(UserText.duckPlayerNativeWatchOnYouTube)
                                        .daxButton()
                                        .daxBodyRegular()
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .frame(height: Constants.bottomButtonHeight)
                    .padding(.horizontal, Constants.horizontalPadding)
                    .padding(.bottom, Constants.horizontalPadding)
                } else {
                    Spacer()
                }

            }
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Check if the drag was predominantly downward and had enough velocity
                    if gesture.translation.height > 100 && gesture.predictedEndTranslation.height > 0 {
                        dismiss()
                    }
                }
        )
        .onFirstAppear {
            viewModel.onFirstAppear()
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    private var header: some View {
        HStack(spacing: Constants.horizontalPadding) {

            // Settings Button
            Button {
                viewModel.openSettings()
                dismiss()
            } label: {
                ZStack {
                    Image(Constants.duckPlayerSettingsImage)
                    .foregroundColor(.white)
                }
            }

            Spacer()

            HStack {
                Image(Constants.daxLogo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Constants.daxLogoSize, height: Constants.daxLogoSize)

                Text(UserText.duckPlayerFeatureName)
                    .foregroundColor(.white)
                    .font(.headline)
            }

            Spacer()

            // Close Button
            Button(action: { dismiss() }, label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44) // Larger touch target
            })
        }
        .padding(.horizontal, Constants.horizontalPadding)
    }
}
