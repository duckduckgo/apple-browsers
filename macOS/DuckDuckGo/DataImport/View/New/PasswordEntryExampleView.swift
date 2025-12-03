//
//  PasswordEntryExampleView.swift
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

struct PasswordEntryExampleView: View {
    let helpText: String?
    let scale: CGFloat

    init(helpText: String? = nil, scale: CGFloat = 1.0) {
        self.helpText = helpText
        self.scale = scale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            promptImage
            if let helpText {
                helpTextView(helpText)
            } else {
                textPlaceholders
            }
            buttonArea
            cursor
        }
        .frame(width: Metrics.containerImageWidth * scale, height: Metrics.containerImageHeight * scale)
    }

    private var promptImage: some View {
        Image(.importKeychainPromptContainer)
            .resizable()
            .frame(width: Metrics.containerImageWidth * scale, height: Metrics.containerImageHeight * scale)
    }

    private func helpTextView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13 * scale))
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 244 * scale, alignment: .leading)
            .padding(.top, 28 * scale)
            .padding(.leading, 104 * scale)
    }

    private var textPlaceholders: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            textPlaceholder(width: 244 * scale)
            textPlaceholder(width: 183 * scale)
        }
        .padding(.top, 28 * scale)
        .padding(.leading, 104 * scale)
    }

    private var buttonArea: some View {
        HStack(spacing: Metrics.spacing * scale) {
            placeholderButton
            allowButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Metrics.spacing * 2 * scale)
        .padding(.bottom, 35 * scale)
    }

    private var cursor: some View {
        Image(.chromiumImportCursor)
            .scaleEffect(scale, anchor: .bottomTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var placeholderButton: some View {
        placeholderRect(width: 80 * scale, cornerRadius: Metrics.buttonCornerRadius * scale)
    }

    private var allowButton: some View {
        Text(UserText.importChromeAllowButtonTitle)
            .font(.system(size: 13 * scale))
            .padding(.horizontal, Metrics.spacing * scale)
            .frame(height: Metrics.itemHeight * scale)
            .background(
                placeholderRect(cornerRadius: Metrics.buttonCornerRadius * scale)
            )
    }

    private func textPlaceholder(width: CGFloat) -> some View {
        placeholderRect(width: width, cornerRadius: Metrics.itemHeight * scale / 2.0)
    }

    private func placeholderRect(width: CGFloat? = nil, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(designSystemColor: .containerFillTertiary))
            .frame(width: width, height: Metrics.itemHeight * scale)
    }
}

// MARK: - Metrics

private extension PasswordEntryExampleView {
    enum Metrics {
        static let itemHeight: CGFloat = 20
        static let spacing: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 5
        static let containerImageWidth: CGFloat = 380
        static let containerImageHeight: CGFloat = 160
    }
}

#Preview {
    VStack(spacing: 20) {
        PasswordEntryExampleView()
        
        PasswordEntryExampleView(scale: 0.75)
        
        PasswordEntryExampleView(scale: 0.5)

        PasswordEntryExampleView(helpText: UserText.passwordEntryHelpDialogExampleText)
        
        PasswordEntryExampleView(helpText: UserText.passwordEntryHelpDialogExampleText, scale: 0.75)
    }
}
