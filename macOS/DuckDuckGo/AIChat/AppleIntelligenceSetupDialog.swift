//
//  AppleIntelligenceSetupDialog.swift
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

/// Shown when the user picks Apple Intelligence for page summaries but it isn't turned on or ready.
struct AppleIntelligenceSetupDialog: ModalView {

    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager
    @Environment(\.dismiss) private var dismiss

    private let openSystemSettings: () -> Void

    init(openSystemSettings: @escaping () -> Void = { NSWorkspace.shared.open(.appleIntelligenceSystemSettings) }) {
        self.openSystemSettings = openSystemSettings
    }

    var body: some View {
        VStack(spacing: 16) {
            AppleIntelligenceIcon()

            Text(UserText.appleIntelligenceSetupTitle)
                .multilineTextAlignment(.center)
                .fixMultilineScrollableText()
                .font(.system(size: 15).weight(.semibold))
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                Button {
                    openSystemSettings()
                    dismiss()
                } label: {
                    Text(UserText.appleIntelligenceSetupOpenSettings)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, stateColors: .themedActionButton, pillShape: true))
                .keyboardShortcut(.defaultAction)

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
        }
        .padding(20)
        .frame(width: 330)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
    }
}

/// A stand-in until the design's Apple Intelligence artwork is in the asset catalog.
private struct AppleIntelligenceIcon: View {

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.78, blue: 0.98),
                                              Color(red: 0.69, green: 0.49, blue: 0.96),
                                              Color(red: 0.96, green: 0.36, blue: 0.51),
                                              Color(red: 0.98, green: 0.76, blue: 0.40)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 64, height: 64)
            symbol
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(.white)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var symbol: some View {
        if #available(macOS 15.1, *) {
            Image(systemName: "apple.intelligence")
        } else {
            Image(systemName: "sparkles")
        }
    }
}
