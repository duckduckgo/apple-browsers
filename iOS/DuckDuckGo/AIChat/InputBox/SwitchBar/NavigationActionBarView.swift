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
import Combine

// MARK: - NavigationActionBarView

struct NavigationActionBarView: View {

    // MARK: - Properties
    @ObservedObject var viewModel: NavigationActionBarViewModel
    @StateObject private var keyboardObserver = KeyboardObserver()

    // MARK: - Constants
    private enum Constants {
        static let barHeight: CGFloat = 76
        static let buttonSize: CGFloat = 44
        static let padding: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let cornerRadius: CGFloat = 8

        static let shadowRadius1: CGFloat = 6
        static let shadowOffset1Y: CGFloat = 2
        static let shadowRadius2: CGFloat = 16
        static let shadowOffset2Y: CGFloat = 16
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
                if viewModel.hasText {
                    searchButton
                }
            }
        }
        .padding(Constants.padding)
        .background(
            Group {
                if keyboardObserver.isKeyboardVisible {
                    VStack (spacing: 0) {
                        Spacer()
                            .frame(height: Constants.padding)

                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(designSystemColor: .surface).opacity(0.0),
                                Color(designSystemColor: .surface).opacity(0.8)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                         .frame(height: Constants.barHeight)

                        /// Add a color bellow the top gradient so it doesn't show a cut-off during keyboard animations
                        /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210809108643486?focus=true
                        Color(designSystemColor: .surface).opacity(0.8)
                    }
                    /// Overflow the color
                    .frame(height: 140)
                    .clipped()
                    .ignoresSafeArea(.container, edges: .horizontal)
                }
            }
        )
    }

    // MARK: - Button Views

    private var webSearchToggleButton: some View {
        CircularButton(
            action: viewModel.handleWebSearchToggle,
            icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.globe),
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
        let icon: Image = {
            if viewModel.isCurrentTextValidURL {
                return Image(uiImage: DesignSystemImages.Glyphs.Size24.globe)
            } else if viewModel.isSearchMode {
                return Image(uiImage: DesignSystemImages.Glyphs.Size24.searchFind)
            } else {
                return Image(uiImage: DesignSystemImages.Glyphs.Size24.arrowUp)
            }
        }()
        
        return CircularButton(
            action: viewModel.onSearchTapped,
            icon: icon,
            foregroundColor: viewModel.hasText ? .white : Color(designSystemColor: .textPlaceholder),
            backgroundColor: viewModel.hasText ? Color(designSystemColor: .accent) : Color(designSystemColor: .surface),
            isEnabled: viewModel.hasText
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.hasText)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isCurrentTextValidURL)
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
                        color: Color(designSystemColor: .shadowSecondary),
                        radius: Constants.shadowRadius1,
                        x: 0,
                        y: Constants.shadowOffset1Y
                    )
                    .shadow(
                        color: Color(designSystemColor: .shadowSecondary),
                        radius: Constants.shadowRadius2,
                        x: 0,
                        y: Constants.shadowOffset2Y
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isEnabled)
        }
    }
}

// MARK: - KeyboardObserver

private final class KeyboardObserver: ObservableObject {
    @Published private(set) var isKeyboardVisible = false
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        observeKeyboard()
    }
    
    private func observeKeyboard() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = true
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = false
            }
            .store(in: &cancellables)
    }
}
