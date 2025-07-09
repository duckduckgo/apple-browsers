//
//  NavigationActionBarView.swift
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
import DesignResourcesKitIcons
import DesignResourcesKit

// MARK: - NavigationActionBarView

struct NavigationActionBarView: View {

    // MARK: - Properties
    @ObservedObject var viewModel: NavigationActionBarViewModel

    // MARK: - Constants
    private enum Constants {
        static let barHeight: CGFloat = 76
        static let buttonSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let cornerRadius: CGFloat = 8
        static let shadowRadius: CGFloat = 1
        static let shadowOffset: CGFloat = 0
    }

    // MARK: - Initializer
    init(viewModel: NavigationActionBarViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        HStack(spacing: Constants.buttonSpacing) {
            if !viewModel.isSearchMode {
                webSearchToggleButton
            }

            Spacer()

            HStack(spacing: Constants.buttonSpacing) {
                if viewModel.shouldShowMicButton {
                    microphoneButton
                }
                newLineButton
                searchButton
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .frame(height: Constants.barHeight)
    }

    // MARK: - Button Views

    private var webSearchToggleButton: some View {
        CircularButton(
            action: viewModel.handleWebSearchToggle,
            icon: Image(systemName: "globe"),
            foregroundColor: viewModel.isWebSearchEnabled ? .white : .primary,
            backgroundColor: viewModel.isWebSearchEnabled ? Color(designSystemColor: .accent) : Color(designSystemColor: .surface)
        )
        .transition(.scale.combined(with: .opacity))
    }

    private var microphoneButton: some View {
        CircularButton(
            action: viewModel.onMicrophoneTapped,
            icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.microphone),
            isEnabled: viewModel.isVoiceSearchEnabled
        )
        .opacity(viewModel.isVoiceSearchEnabled ? 1.0 : 0.5)
    }

    private var newLineButton: some View {
        CircularButton(
            action: viewModel.onNewLineTapped,
            icon: Image(systemName: "return")
        )
    }

    private var searchButton: some View {
        CircularButton(
            action: viewModel.onSearchTapped,
            icon: Image(uiImage: viewModel.isSearchMode ? DesignSystemImages.Glyphs.Size16.findSearch : DesignSystemImages.Glyphs.Size16.sendPlane),
            foregroundColor: viewModel.hasText ? .white : Color(designSystemColor: .textPlaceholder),
            backgroundColor: viewModel.hasText ? Color(designSystemColor: .accent) : Color(designSystemColor: .surface),
            isEnabled: viewModel.hasText
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.hasText)
    }

    // MARK: - CircularButton

    private struct CircularButton<Icon: View>: View {
        let action: () -> Void
        let icon: Icon
        var foregroundColor: Color = .primary
        var backgroundColor: Color = Color(designSystemColor: .surface)
        var isEnabled: Bool = true

        var body: some View {
            Button(action: action) {
                icon
                    .font(.system(size: 18))
                    .foregroundColor(foregroundColor)
                    .frame(width: Constants.buttonSize,
                           height: Constants.buttonSize)
                    .background(
                        Circle()
                            .fill(backgroundColor)
                    )
                    .shadow(
                        color: Color(designSystemColor: .shadowPrimary),
                        radius: Constants.shadowRadius,
                        x: 0,
                        y: Constants.shadowOffset
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isEnabled)
        }
    }
}
