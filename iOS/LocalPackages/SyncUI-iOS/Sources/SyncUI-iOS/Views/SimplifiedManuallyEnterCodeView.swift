//
//  SimplifiedManuallyEnterCodeView.swift
//  DuckDuckGo
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI

public struct SimplifiedManuallyEnterCodeView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel

    public init(model: ScanOrPasteCodeViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack {
            mainPanel
                .padding(.horizontal, 16)
                .padding(.top, 20)

            Spacer()
        }
        .background(SimplifiedSyncStyle.screenBackground)
        .navigationTitle(UserText.manuallyEnterCodeTitle)
        .modifier(BackButtonModifier())
        .onAppear {
            model.delegate?.codeEntryScreenShown()
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 16) {
            contentArea

            pasteButton
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(SimplifiedSyncStyle.subduedPanelBackground)
        )
    }

    // MARK: - Content area

    /// Invisible text that matches the code display font to provide a consistent minimum height for the content area.
    private var sizingGuide: some View {
        Text(String(repeating: " \n", count: Constants.codeLineLimit))
            .codeDisplayStyle()
            .hidden()
    }

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            sizingGuide

            if let code = model.manuallyEnteredCode {
                codeView(code: code)
            } else {
                instructionsView
            }
        }
    }

    private func codeView(code: String) -> some View {
        Text(code)
            .codeDisplayStyle()
            .foregroundColor(.white)
    }

    private var verifyingView: some View {
        HStack(spacing: 4) {
            SwiftUI.ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(designSystemColor: .textTertiary)))
            Text(UserText.simplifiedPasteCodeVerifying)
                .font(.body)
                .foregroundColor(Color(designSystemColor: .textTertiary))
        }
        .opacity(model.isValidating ? 1 : 0)
    }

    private var instructionsView: some View {
        Text(LocalizedStringKey(UserText.simplifiedPasteCodeInstructions))
            .font(.body)
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    private var pasteButton: some View {
        VStack(alignment: .center, spacing: 12) {
            verifyingView

            Button(action: model.pasteCode) {
                HStack(spacing: 8) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.paste)
                        .frame(width: 16, height: 16)
                    Text(UserText.pasteButton)
                        .daxButton()
                }
                .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SimplifiedSyncStyle.primaryActionBackground)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private enum Constants {
        static let codeLineLimit: Int = 6
    }
}

// MARK: - Code Display Style

private extension Text {
    func codeDisplayStyle() -> some View {
        self
            .kerning(2)
            .monospaceSystemFont(ofSize: 16)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 10)
    }
}
