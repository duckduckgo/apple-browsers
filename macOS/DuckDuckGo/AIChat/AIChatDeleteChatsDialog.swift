//
//  AIChatDeleteChatsDialog.swift
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

import AppKit
import SwiftUI
import SwiftUIExtensions

struct AIChatDeleteChatsDialog: ModalView {

    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    @Environment(\.dismiss) private var dismiss

    var confirmed: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(themeManager.isAppRebranded ? .burnAlert : .fireChatLegacy)

            VStack(spacing: 8) {
                Text(UserText.aiChatMenuDeleteAllChatsDialogTitle)
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 15).weight(.semibold))

                Text(UserText.aiChatMenuDeleteAllChatsAlertMessage)
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Text(UserText.cancel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true))
                .keyboardShortcut(.cancelAction)

                Button {
                    confirmed?()
                    dismiss()
                } label: {
                    Text(UserText.aiChatMenuDeleteAllChatsConfirmButton)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DestructiveActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, pillShape: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 330)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
    }
}
