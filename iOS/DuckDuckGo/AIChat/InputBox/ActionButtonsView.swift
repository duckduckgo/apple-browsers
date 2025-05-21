//
//  ActionButtonsView.swift
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
import UIKit

struct ActionButtonsView: View {
    let mode: AIChatInputBoxViewModel.InputMode
    let onDuckAssistTapped: () -> Void
    let onVoiceTapped: () -> Void
    let onWebAnswerTapped: () -> Void
    let onSendTapped: () -> Void
    let isSendEnabled: Bool
    
    @State private var isDuckAssistEnabled = false
    @State private var isWebAnswerEnabled = false
    
    var body: some View {
        HStack(spacing: 16) {
            if mode == .search {
                Button(action: {
                    isDuckAssistEnabled.toggle()
                    onDuckAssistTapped()
                }) {
                    Image(systemName: "list.star")
                        .foregroundColor(isDuckAssistEnabled ? .blue : .gray)
                }
                
                Spacer()
                
                Button(action: onVoiceTapped) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.blue)
                }
                
                Button(action: onSendTapped) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundColor(isSendEnabled ? .blue : .gray)
                }
                .font(.system(size: 30, weight: .medium))
                .disabled(!isSendEnabled)
            } else {
                Button(action: {
                    isWebAnswerEnabled.toggle()
                    onWebAnswerTapped()
                }) {
                    Image(systemName: "globe")
                        .foregroundColor(isWebAnswerEnabled ? .blue : .gray)
                }
                
                Spacer()
                
                Button(action: onVoiceTapped) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.blue)
                }
                
                Button(action: onSendTapped) {
                    Image(systemName: "paperplane.circle.fill")
                        .foregroundColor(isSendEnabled ? .blue : .gray)
                }
                .font(.system(size: 30, weight: .medium))

                .disabled(!isSendEnabled)
            }
        }
        .font(.system(size: 20, weight: .medium))

        .padding(.horizontal, 8)
    }
}

#Preview {
    ActionButtonsView(mode: .chat, onDuckAssistTapped: {}, onVoiceTapped: {}, onWebAnswerTapped: {}, onSendTapped: {}, isSendEnabled: true)
}
