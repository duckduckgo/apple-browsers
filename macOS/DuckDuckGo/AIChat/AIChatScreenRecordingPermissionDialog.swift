//
//  AIChatScreenRecordingPermissionDialog.swift
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
import DesignResourcesKit
import SwiftUI
import SwiftUIExtensions

/// Shown when a Duck.ai screenshot needs Screen Recording. Its own view rather than an `NSAlert`, which
/// recent macOS lays out left-aligned.
struct AIChatScreenRecordingPermissionDialog: ModalView {

    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    @Environment(\.dismiss) private var dismiss

    /// Continue asks macOS; once macOS has been asked, the button is Open System Settings.
    private let asksMacOS: Bool
    private let confirmed: () -> Void

    init(asksMacOS: Bool, confirmed: @escaping () -> Void) {
        self.asksMacOS = asksMacOS
        self.confirmed = confirmed
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(.duckDuckGoResponseQuestion96)
                .resizable()
                .frame(width: 76, height: 76)

            VStack(spacing: 8) {
                Text(UserText.screenRecordingPermissionTitle)
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 15).weight(.semibold))

                Text(asksMacOS ? UserText.screenRecordingPermissionMessage : UserText.screenRecordingPermissionSettingsMessage)
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            .padding(.bottom, 8)

            // Open System Settings doesn't fit beside Not Now, so it stacks above it, like a native alert.
            if asksMacOS {
                HStack(spacing: 8) {
                    notNowButton
                    confirmButton
                }
            } else {
                VStack(spacing: 8) {
                    confirmButton
                    notNowButton
                }
            }
        }
        .padding(20)
        .frame(width: 330)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
    }

    private var notNowButton: some View {
        Button {
            dismiss()
        } label: {
            Text(UserText.notNow)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        }
        .buttonStyle(DismissActionButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true, stateColors: .themedDismissButton))
        .keyboardShortcut(.cancelAction)
    }

    private var confirmButton: some View {
        Button {
            confirmed()
            dismiss()
        } label: {
            Text(asksMacOS ? UserText.continue : UserText.screenRecordingPermissionOpenSettings)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        }
        .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, stateColors: .themedActionButton, pillShape: true))
        .keyboardShortcut(.defaultAction)
    }
}
