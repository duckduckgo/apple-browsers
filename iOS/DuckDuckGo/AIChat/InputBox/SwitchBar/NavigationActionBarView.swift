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

// MARK: - NavigationActionBarView

struct NavigationActionBarView: View {
    
    // MARK: - Properties
    @State private var isSearchMode: Bool = true
    @State private var hasText: Bool = false
    @State private var isWebSearchEnabled: Bool = false
    @State private var isVoiceSearchEnabled: Bool = true
    @State private var isInInitialSelectedState: Bool = false
    
    // MARK: - Action Callbacks
    let onMicrophoneTapped: () -> Void
    let onNewLineTapped: () -> Void
    let onSearchTapped: () -> Void
    let onWebSearchToggled: () -> Void
    
    // MARK: - Constants
    private enum Constants {
        static let barHeight: CGFloat = 44
        static let buttonSize: CGFloat = 32
        static let horizontalPadding: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let cornerRadius: CGFloat = 8
    }
    
    // MARK: - Initializer
    init(onMicrophoneTapped: @escaping () -> Void = {},
         onNewLineTapped: @escaping () -> Void = {},
         onSearchTapped: @escaping () -> Void = {},
         onWebSearchToggled: @escaping () -> Void = {}) {
        self.onMicrophoneTapped = onMicrophoneTapped
        self.onNewLineTapped = onNewLineTapped
        self.onSearchTapped = onSearchTapped
        self.onWebSearchToggled = onWebSearchToggled
    }
    
    var body: some View {
        HStack(spacing: Constants.buttonSpacing) {
            // Left side - Web search toggle (only in AI Chat mode)
            if !isSearchMode {
                webSearchToggleButton
            }
            
            Spacer()
            
            // Right side buttons
            HStack(spacing: Constants.buttonSpacing) {
                if shouldShowMicButton {
                    microphoneButton
                }
                newLineButton
                searchButton
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .frame(height: Constants.barHeight)
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.black.opacity(0.1))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    // MARK: - Computed Properties
    
    /// Matches the logic from SwitchBarTextEntryView for mic button visibility
    private var shouldShowMicButton: Bool {
        if isInInitialSelectedState && hasText {
            return true // initialSelected state shows both mic and clear
        } else if !hasText && isVoiceSearchEnabled {
            return true // micOnly state when no text and voice search enabled
        } else {
            return false
        }
    }
    
    // MARK: - Button Views
    
    private var webSearchToggleButton: some View {
        Button(action: {
            onWebSearchToggled()
            isWebSearchEnabled.toggle()
        }) {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundColor(isWebSearchEnabled ? .white : .primary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(isWebSearchEnabled ? Color.accentColor : Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .transition(.scale.combined(with: .opacity))
    }
    
    private var microphoneButton: some View {
        Button(action: onMicrophoneTapped) {
            Image(systemName: "mic.fill")
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isVoiceSearchEnabled ? 1.0 : 0.5)
        .disabled(!isVoiceSearchEnabled)
    }
    
    private var newLineButton: some View {
        Button(action: onNewLineTapped) {
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
        Button(action: onSearchTapped) {
            Image(systemName: isSearchMode ? "magnifyingglass" : "paperplane.fill")
                .font(.system(size: 18))
                .foregroundColor(.white)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(hasText ? Color.accentColor : Color.gray)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!hasText)
        .animation(.easeInOut(duration: 0.2), value: hasText)
    }
    
    // MARK: - Public Methods
    
    /// Updates the view state based on external changes
    func updateState(isSearchMode: Bool, hasText: Bool, isWebSearchEnabled: Bool, isVoiceSearchEnabled: Bool, isInInitialSelectedState: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isSearchMode = isSearchMode
            self.hasText = hasText
            self.isWebSearchEnabled = isWebSearchEnabled
            self.isVoiceSearchEnabled = isVoiceSearchEnabled
            self.isInInitialSelectedState = isInInitialSelectedState
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // Search mode
        NavigationActionBarView()
        
        // AI Chat mode with web search enabled
        NavigationActionBarView()
            .onAppear {
                // Simulate AI chat mode
            }
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
