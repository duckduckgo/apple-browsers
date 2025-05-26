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
        static let daxLogo = "Home"
        static let duckPlayerImage: String = "DuckPlayer"
        static let duckPlayerSettingsImage: String = "DuckPlayerOpenSettings"
        static let duckPlayerYoutubeImage: String = "OpenInYoutube"
        static let dragGestureThreshold: CGFloat = 100
        static let uiElementsBackground: Color = Color.gray.opacity(0.2)
        static let uiElementRadius: CGFloat = 8
        static let chevronUpIcon: String = "chevron.up"
    }

    enum LayoutConstants {
        static let headerHeight: CGFloat = 56
        static let iconSize: CGFloat = 32
        static let cornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 16
        static let daxLogoSize: CGFloat = 24.0
        static let bottomButtonHeight: CGFloat = 44
        static let grabHandleHeight: CGFloat = 4
        static let grabHandleWidth: CGFloat = 36
        static let grabHandlePadding: CGFloat = 8
        static let videoContainerPadding: CGFloat = 20
        static let welcomeMessageSpacing: CGFloat = 16
        static let welcomeMessageInternalPadding: CGFloat = 10
        static let welcomeMessageCornerRadius: CGFloat = 12
        static let welcomeMessagePadding: CGFloat = 16
        static let welcomeMessageExternalPadding: CGFloat = 5
        static let duckPlayerLogoSize: CGFloat = 55
        static let duckPlayerLogoSpacing: CGFloat = 16
        static let defaultSpacing: CGFloat = 8
        static let youtubeButtonsize: CGFloat = 24
        static let settingsButtonSize: CGFloat = 20
        static let closeButtonSize: CGFloat = 44
        static let bubbleCloseButtonSize: CGFloat = 32
        static let controlsSpacing: CGFloat = 8
        static let controlButtonSize: CGFloat = 30
        static let controlIconSize: CGFloat = 10
        static let controlButtonBottomPadding: CGFloat = 10
        static let animationResponseTime: Double = 0.4
        static let animationDampingFraction: Double = 0.8
    }

    var body: some View {
        return ZStack {
            // Background with blur effect
            Color(.black)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Grab Handle
                if !viewModel.isLandscape {
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: LayoutConstants.grabHandleWidth, height: LayoutConstants.grabHandleHeight)
                        .padding(.top, LayoutConstants.grabHandlePadding)
                }

                // Header
                if !viewModel.isLandscape {
                    header
                        .frame(height: LayoutConstants.headerHeight)
                }

                // Video Container
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
                .layoutPriority(1)

                Spacer(minLength: LayoutConstants.controlsSpacing)

                // Controls Container
                VStack(spacing: 4) {
                    if viewModel.controlsVisible {
                        // Show only if the source is youtube and the toggle should be visible
                        autoOpenToggleView
                            .transition(.move(edge: .bottom).combined(with: .opacity))

                        // Show the youtube button if needed
                        youtubeButtonView
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: LayoutConstants.animationResponseTime, dampingFraction: LayoutConstants.animationDampingFraction), value: viewModel.controlsVisible)
                .frame(minWidth: 0, maxWidth: .infinity)
                .padding(.bottom, viewModel.controlsVisible ?  LayoutConstants.controlsSpacing: 0)

                // Show the welcome message if needed
                welcomeMessage

                if !viewModel.shouldShowWelcomeMessage && !viewModel.isLandscape {
                    // Toggle Controls Button
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: LayoutConstants.controlButtonSize, height: LayoutConstants.controlButtonSize)

                        Button(action: {
                            withAnimation(.spring(response: LayoutConstants.animationResponseTime, dampingFraction: LayoutConstants.animationDampingFraction)) {
                                viewModel.controlsVisible.toggle()
                            }
                        }) {
                            Image(systemName: Constants.chevronUpIcon)
                                .font(.system(size: LayoutConstants.controlIconSize, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: LayoutConstants.controlButtonSize, height: LayoutConstants.controlButtonSize)
                                .rotationEffect(Angle(degrees: viewModel.controlsVisible ? 180 : 0))
                        }
                    }
                    .padding(.bottom, LayoutConstants.controlButtonBottomPadding)
                }
            }
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Check if the drag was predominantly downward and had enough velocity
                    if gesture.translation.height > Constants.dragGestureThreshold && gesture.predictedEndTranslation.height > 0 {
                        dismiss()
                    }
                }
        )
        .onFirstAppear {
            viewModel.onFirstAppear()
            autoOpenOnYoutube = viewModel.autoOpenOnYoutube
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    @ViewBuilder
    private var autoOpenToggleView: some View {
        if viewModel.showAutoOpenOnYoutubeToggle && viewModel.source == .youtube {
            ZStack {
                RoundedRectangle(cornerRadius: Constants.uiElementRadius)
                    .fill(Constants.uiElementsBackground)
                HStack(spacing: 8) {
                    Text(UserText.duckPlayerSettingsToggle)
                        .daxBodyRegular()
                        .foregroundColor(.white)
                    Spacer()
                    Toggle(isOn: $autoOpenOnYoutube) {}
                        .labelsHidden()
                        .tint(.init(designSystemColor: .accent))
                        .onChange(of: autoOpenOnYoutube) { newValue in
                            viewModel.autoOpenOnYoutube = newValue
                        }
                }
                .padding(.horizontal, LayoutConstants.horizontalPadding)
            }
            .frame(height: LayoutConstants.bottomButtonHeight)
            .padding(.horizontal, LayoutConstants.horizontalPadding)
            .padding(.bottom, LayoutConstants.controlsSpacing)
            .transition(.opacity)
            .animation(.easeInOut, value: showOpenInYoutubeToggle)
        }
    }

    @ViewBuilder
    private var youtubeButtonView: some View {
        if viewModel.shouldShowYouTubeButton {
            ZStack {
                RoundedRectangle(cornerRadius: LayoutConstants.defaultSpacing)
                    .fill(Constants.uiElementsBackground)
                Button {
                    viewModel.openInYouTube()
                } label: {
                    HStack(spacing: LayoutConstants.defaultSpacing) {
                        Text(UserText.duckPlayerWatchOnYoutube)
                            .daxBodyRegular()
                            .foregroundColor(.white)
                        Spacer()
                        Image(Constants.duckPlayerYoutubeImage)
                            .renderingMode(.template)
                            .foregroundColor(.white)
                            .frame(width: LayoutConstants.youtubeButtonsize, height: LayoutConstants.youtubeButtonsize)
                    }
                    .padding(.horizontal, LayoutConstants.horizontalPadding)
                }
            }
            .frame(height: LayoutConstants.bottomButtonHeight)
            .padding(.horizontal, LayoutConstants.horizontalPadding)
            .padding(.bottom, 8)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: LayoutConstants.horizontalPadding) {

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
                        .frame(width: LayoutConstants.settingsButtonSize, height: LayoutConstants.settingsButtonSize)
                }
            }

            Spacer()

            HStack {
                Image(Constants.daxLogo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: LayoutConstants.daxLogoSize, height: LayoutConstants.daxLogoSize)

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
                        .frame(width: LayoutConstants.closeButtonSize, height: LayoutConstants.closeButtonSize)
                })
        }
        .padding(.horizontal, LayoutConstants.horizontalPadding)
    }

   @ViewBuilder
  private var bubbleContent: some View {
    VStack(alignment: .leading, spacing: LayoutConstants.defaultSpacing) {
        Text(UserText.duckPlayerWelcomeMessageTitle)
            .daxHeadline()
            .foregroundColor(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)

        Text(UserText.duckPlayerWelcomeMessageContent)
            .daxBodyRegular()
            .foregroundColor(.white.opacity(0.8))
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)

        // Toggle
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
            HStack(spacing: 8) {
                Text(UserText.duckPlayerSettingsToggle)
                    .daxBodyRegular()
                    .foregroundColor(.white)
                Spacer()
                Toggle(isOn: $autoOpenOnYoutube) {}
                    .labelsHidden()
                    .tint(.init(designSystemColor: .accent))
                    .onChange(of: autoOpenOnYoutube) { newValue in
                        viewModel.autoOpenOnYoutube = newValue
                    }
            }
            .padding(.horizontal, LayoutConstants.horizontalPadding)
        }
        .frame(height: LayoutConstants.bottomButtonHeight)
        .padding(.top, LayoutConstants.welcomeMessageSpacing)
    }
    .padding(LayoutConstants.welcomeMessageInternalPadding)
  }

    @ViewBuilder
    private var welcomeMessage: some View {
        if viewModel.shouldShowWelcomeMessage && !viewModel.isLandscape {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading) {
                    HStack {
                        Image(Constants.daxLogo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: LayoutConstants.duckPlayerLogoSize, height: LayoutConstants.duckPlayerLogoSize, alignment: .leading)
                            .padding(.leading, LayoutConstants.welcomeMessageInternalPadding)
                    }

                  BubbleView(
                      arrowLength: 15,
                      arrowWidth: 25,
                      arrowPositionPercent: 1,
                      fillColor: Constants.uiElementsBackground,
                      paddingAmount: LayoutConstants.welcomeMessageInternalPadding
                  ) {
                      bubbleContent
                        .padding(LayoutConstants.welcomeMessageInternalPadding)
                  }
                  .offset(x: 0, y: 2)
                  .padding(.horizontal, LayoutConstants.horizontalPadding)
                }

                // Close Button
                Button(action: {
                    viewModel.hideWelcomeMessage()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.2, opacity: 1.0))
                            .frame(width: LayoutConstants.bubbleCloseButtonSize, height: LayoutConstants.bubbleCloseButtonSize)

                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(8)
                }
                .offset(x: 2, y: 4 + LayoutConstants.duckPlayerLogoSize)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
            }
            .transition(.opacity)
        }
    }

}
