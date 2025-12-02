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
                    .frame(width: 16, height: 16)
                    .offset(y: 1)
            }
            .frame(width: 50)

            VStack(alignment: .leading, spacing: 20) {
                titleSection
                instructionsText
                showMessageButton
                keychainPromptExample
            }
            .padding(.trailing, 50)
        }
        .padding(.top, 40)
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
        PasswordEntryExampleView(helpText: UserText.passwordEntryHelpDialogExampleText)
            .padding(.bottom, 40)
    }
}
