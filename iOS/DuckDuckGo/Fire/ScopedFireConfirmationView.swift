//
//  ScopedFireConfirmationView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Core
import DuckUI
import Lottie

struct ScopedFireConfirmationView: View {
    
    @ObservedObject var viewModel: ScopedFireConfirmationViewModel
    @State private var isAnimating = false
    
    init(viewModel: ScopedFireConfirmationViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                contentView
                    .padding(Constants.viewPadding)
            }
            .modifier(ScrollBounceBehaviorModifier())
            closeButton
                .padding(16)
        }
        .background(Color(designSystemColor: .backgroundTertiary))
    }
    
    private var contentView: some View {
        VStack(spacing: Constants.mainSectionSpacing) {
            headerSection
            scopeButtons
        }
    }
    
    private var closeButton: some View {
        Button(action: {
            viewModel.cancel()
        }) {
            Image(uiImage: DesignSystemImages.Glyphs.Size16.close)
                .foregroundColor(Color(designSystemColor: .icons))
                .padding(Constants.closeButtonPadding)
                .background(Color(designSystemColor: .controlsFillPrimary))
                .clipShape(Circle())
        }
        .accessibilityIdentifier("Fire.Confirmation.Button.Close")
    }
    
    private var headerSection: some View {
        VStack(spacing: Constants.headerSectionSpacing) {
            animation
            
            VStack(spacing: Constants.headlineTextSpacing) {
                Text(viewModel.headerTitle)
                    .daxTitle3()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = viewModel.subtitle {
                    Text(subtitle)
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Constants.headerSectionPadding)
    }
    
    /// Scope selection buttons
    private var scopeButtons: some View {
        VStack(spacing: Constants.buttonSpacing) {
            // All Tabs button - Primary Destructive (filled)
            Button(action: {
                viewModel.burnAllTabs()
            }) {
                Text(UserText.scopedFireConfirmationDeleteAllButton)
            }
            .buttonStyle(PrimaryDestructiveButtonStyle())
            .accessibilityIdentifier("Fire.Confirmation.Button.AllTabs")
            
            // This Tab button - Secondary Destructive (outline)
            if viewModel.canBurnSingleTab {
                Button(action: {
                    viewModel.burnThisTab()
                }) {
                    Text(UserText.scopedFireConfirmationDeleteThisTabButton)
                }
                .buttonStyle(SecondaryDestructiveButtonStyle())
                .accessibilityIdentifier("Fire.Confirmation.Button.ThisTab")
            }
        }
    }
    
    @ViewBuilder
    private var animation: some View {
        Lottie.LottieView(animation: .named("fire-icon"))
            .playbackMode(isAnimating ? .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)) : .paused(at: .progress(0)))
            .resizable()
            .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + Constants.animationDelay) {
                    isAnimating = true
                }
            }
    }
    
}

private extension ScopedFireConfirmationView {
    enum Constants {
        static let viewPadding: EdgeInsets = .init(top: 24, leading: 24, bottom: 64, trailing: 24)
        static let mainSectionSpacing: CGFloat = 16
        static let headerSectionSpacing: CGFloat = 8
        static let headerSectionPadding: EdgeInsets = .init(top: 24, leading: 0, bottom: 16, trailing: 0)
        static let headerIconSize: CGFloat = 96
        static let headlineTextSpacing: CGFloat = 4
        static let buttonSpacing: CGFloat = 16
        static let closeButtonPadding: CGFloat = 8
        static let animationDelay: Double = 0.5
    }
}
