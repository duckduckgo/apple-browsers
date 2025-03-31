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

import DesignResourcesKit
import Foundation
import SwiftUI

struct DuckPlayerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var viewModel: DuckPlayerViewModel
    var webView: DuckPlayerWebView

    // Local state for auto open on Youtube toggle
    @State private var autoOpenOnYoutube: Bool = false

    // Local state & Task for hiding the auto open on Youtube toggle after 2 seconds
    @State private var hideToggleTask: DispatchWorkItem?
    @State private var showOpenInYoutubeToggle: Bool = true

    enum Constants {
        static let headerHeight: CGFloat = 56
        static let iconSize: CGFloat = 32
        static let cornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 16
        static let daxLogoSize: CGFloat = 24.0
        static let daxLogo = "Home"
        static let duckPlayerImage: String = "DuckPlayer"
        static let duckPlayerSettingsImage: String = "DuckPlayerOpenSettings"
        static let duckPlayerYoutubeImage: String = "OpenInYoutube"
        static let bottomButtonHeight: CGFloat = 44
        static let grabHandleHeight: CGFloat = 4
        static let grabHandleWidth: CGFloat = 36
        static let videoContainerPadding: CGFloat = 20
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
                        height: geometry.size.height
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                }

                // Show only if the source is youtube and the toggle should be visible
                if viewModel.showAutoOpenOnYoutubeToggle && viewModel.source == .youtube && showOpenInYoutubeToggle {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                        HStack(spacing: 8) {
                            Text(UserText.duckPlayerNativeAutoOpenLabel)
                                .daxBodyRegular()
                                .foregroundColor(.white)
                            Spacer()
                            Toggle(isOn: $autoOpenOnYoutube) {}
                                .labelsHidden()
                                .tint(.init(designSystemColor: .accent))
                        }
                        .padding(.horizontal, Constants.horizontalPadding)
                    }
                    .frame(height: Constants.bottomButtonHeight)
                    .padding(.horizontal, Constants.horizontalPadding)
                    .padding(.bottom, Constants.horizontalPadding)
                    .padding(.top, Constants.videoContainerPadding)
                    .transition(.opacity)
                    .animation(.easeInOut, value: showOpenInYoutubeToggle)
                }

                if viewModel.shouldShowYouTubeButton {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                        Button {
                            viewModel.openInYouTube()
                        } label: {
                            HStack(spacing: 8) {
                                Text(UserText.duckPlayerNativeWatchOnYouTube)
                                    .daxBodyRegular()
                                    .foregroundColor(.white)
                                Spacer()
                                Image(Constants.duckPlayerYoutubeImage)
                                    .renderingMode(.template)
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                            }
                            .padding(.horizontal, Constants.horizontalPadding)
                        }
                    }
                    .frame(height: Constants.bottomButtonHeight)
                    .padding(.horizontal, Constants.horizontalPadding)
                    .padding(.bottom, Constants.horizontalPadding)
                    .padding(.top, Constants.videoContainerPadding)
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
            autoOpenOnYoutube = viewModel.autoOpenOnYoutube
            showOpenInYoutubeToggle = !viewModel.autoOpenOnYoutube
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: autoOpenOnYoutube) { newValue in
            // Create a new task to hide the toggle after 2 seconds
            hideToggleTask?.cancel()

            if newValue {

                let task = DispatchWorkItem {
                    withAnimation {
                        showOpenInYoutubeToggle = false
                        viewModel.autoOpenOnYoutube = true
                        viewModel.hideAutoOpenToggle()
                    }
                }

                hideToggleTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
            } else {
                viewModel.autoOpenOnYoutube = false
            }
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
                        .resizable()
                        .foregroundColor(.white)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
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
            Button(
                action: { dismiss() },
                label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)  // Larger touch target
                })
        }
        .padding(.horizontal, Constants.horizontalPadding)
    }

}
