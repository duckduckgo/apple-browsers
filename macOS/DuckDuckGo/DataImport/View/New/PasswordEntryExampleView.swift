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
        .frame(width: Metrics.containerImageWidth, height: Metrics.containerImageHeight)
        .scaleEffect(scale)
        .frame(width: Metrics.containerImageWidth * scale, height: Metrics.containerImageHeight * scale)
    }

    private var promptImage: some View {
        Image(.importKeychainPromptContainer)
            .resizable()
            .frame(width: Metrics.containerImageWidth, height: Metrics.containerImageHeight)
    }

    private func helpTextView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Metrics.fontSize))
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 244, alignment: .leading)
            .padding(.top, 28)
            .padding(.leading, 104)
    }

    private var textPlaceholders: some View {
        VStack(alignment: .leading, spacing: 12) {
            textPlaceholder(width: 244)
            textPlaceholder(width: 183)
        }
        .padding(.top, 28)
        .padding(.leading, 104)
    }

    private var buttonArea: some View {
        HStack(spacing: Metrics.spacing) {
            placeholderButton
            allowButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Metrics.spacing * 2)
        .padding(.bottom, 35)
    }

    private var cursor: some View {
        Image(.chromiumImportCursor)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var placeholderButton: some View {
        placeholderRect(width: 80, cornerRadius: Metrics.buttonCornerRadius)
    }

    private var allowButton: some View {
        Text(UserText.importChromeAllowButtonTitle)
            .font(.system(size: Metrics.fontSize))
            .padding(.horizontal, Metrics.spacing)
            .frame(height: Metrics.itemHeight)
            .background(
                placeholderRect(cornerRadius: Metrics.buttonCornerRadius)
            )
    }

    private func textPlaceholder(width: CGFloat) -> some View {
        placeholderRect(width: width, cornerRadius: Metrics.itemHeight / 2.0)
    }

    private func placeholderRect(width: CGFloat? = nil, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(designSystemColor: .containerFillTertiary))
            .frame(width: width, height: Metrics.itemHeight)
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
        static let fontSize: CGFloat = 13
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
