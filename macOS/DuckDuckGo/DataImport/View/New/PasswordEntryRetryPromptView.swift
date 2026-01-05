//
//  PasswordEntryRetryPromptView.swift
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

import Foundation
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUIExtensions

struct PasswordEntryRetryPromptView: View {
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .center) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.exclamationRecolorableInvert)
                    .resizable()
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                    .offset(y: 1)
            }
            .frame(width: Metrics.iconColumnWidth)

            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                titleSection
                instructionsText
                showMessageButton
                keychainPromptExample
            }
        }
        .padding(.leading, Metrics.leadingPadding)
        .padding(.trailing, Metrics.trailingPadding)
        .padding(.top, Metrics.verticalPadding)
    }

    private var titleSection: some View {
        Text(UserText.passwordEntryHelpTitle)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
    }

    @ViewBuilder
    private var instructionsText: some View {
        if #available(macOS 12, *), let instructionsAttr = try? AttributedString(markdown: UserText.passwordEntryHelpInstructions) {
            Text(instructionsAttr)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        } else {
            Text(UserText.passwordEntryHelpInstructions)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        }
    }

    private var showMessageButton: some View {
        Button {
            onRetry()
        } label: {
            Text(UserText.passwordEntryHelpShowMacOSMessageButton)
                .padding(.horizontal, 12)
        }
        .buttonStyle(DefaultActionButtonStyle(enabled: true))
        .padding(.bottom, 8)
    }

    private var keychainPromptExample: some View {
        PasswordEntryExampleView(helpText: UserText.passwordEntryHelpDialogExampleText, scale: Metrics.exampleViewScale)
            .padding(.bottom, Metrics.verticalPadding)
    }
}

// MARK: - Metrics

private extension PasswordEntryRetryPromptView {
    enum Metrics {
        static let dialogWidth: CGFloat = 420   // Defined in DataImportView

        static let leadingPadding: CGFloat = 8
        static let trailingPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 40

        static let iconSize: CGFloat = 16
        static let iconColumnWidth: CGFloat = 40

        static let contentSpacing: CGFloat = 20

        private static let exampleViewBaseWidth: CGFloat = 380
        private static let availableWidth: CGFloat = dialogWidth - leadingPadding - iconColumnWidth - trailingPadding
        static let exampleViewScale: CGFloat = availableWidth / exampleViewBaseWidth
    }
}
