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

// MARK: - NavigationActionBarView

struct NavigationActionBarView: View {
    
    // MARK: - Properties
    @ObservedObject var viewModel: NavigationActionBarViewModel
    
    // MARK: - Constants
    private enum Constants {
        static let barHeight: CGFloat = 54
        static let buttonSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let cornerRadius: CGFloat = 8
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
        Button(action: {
            viewModel.handleWebSearchToggle()
        }) {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundColor(viewModel.isWebSearchEnabled ? .white : .primary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(viewModel.isWebSearchEnabled ? Color.accentColor : Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .transition(.scale.combined(with: .opacity))
    }
    
    private var microphoneButton: some View {
        Button(action: viewModel.onMicrophoneTapped) {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.microphone)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(viewModel.isVoiceSearchEnabled ? 1.0 : 0.5)
        .disabled(!viewModel.isVoiceSearchEnabled)
    }
    
    private var newLineButton: some View {
        Button(action: viewModel.onNewLineTapped) {
            Image(systemName: "return")
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var searchButton: some View {
        Button(action: viewModel.onSearchTapped) {
            Image(uiImage: viewModel.isSearchMode ? DesignSystemImages.Glyphs.Size16.findSearch : DesignSystemImages.Glyphs.Size16.sendPlane)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(viewModel.hasText ? Color.accentColor : Color.gray)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!viewModel.hasText)
        .animation(.easeInOut(duration: 0.2), value: viewModel.hasText)
    }
    

}
