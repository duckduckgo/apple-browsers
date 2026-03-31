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
        ZStack {
            Color(baseColor: .gray90)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                codeEntryContainer
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                Spacer()
            }
        }
        .navigationTitle(UserText.manuallyEnterCodeTitle)
        .modifier(BackButtonModifier())
        .onAppear {
            model.delegate?.codeEntryScreenShown()
        }
    }

    // MARK: - Code Entry Container

    private var codeEntryContainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            contentArea

            pasteButton
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.09))
        )
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let code = model.manuallyEnteredCode {
            codeView(code: code)
        } else {
            instructionsView
        }
    }

    private func codeView(code: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(code)
                .kerning(2)
                .monospaceSystemFont(ofSize: 16)
                .foregroundColor(.white)
                .lineSpacing(28 - 16)
                .fixedSize(horizontal: false, vertical: true)

            validationStatusView
        }
    }

    @ViewBuilder
    private var validationStatusView: some View {
        if model.isValidating {
            HStack(spacing: 8) {
                SwiftUI.ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(designSystemColor: .textTertiary)))
                Text(UserText.simplifiedPasteCodeVerifying)
                    .font(.system(size: 16))
                    .foregroundColor(Color(designSystemColor: .textTertiary))
            }
        } else if model.invalidCode {
            HStack(spacing: 8) {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.alertRecolorable)
                    .foregroundColor(Color(designSystemColor: .textTertiary))
                Text(UserText.manuallyEnterCodeValidatingCodeFailedAction)
                    .font(.system(size: 16))
                    .foregroundColor(Color(designSystemColor: .textTertiary))
            }
        }
    }

    private var instructionsView: some View {
        Text(LocalizedStringKey(UserText.simplifiedPasteCodeInstructions))
            .font(.system(size: 16))
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Paste Button

    private var pasteButton: some View {
        Button(action: model.pasteCode) {
            HStack(spacing: 8) {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.paste)
                    .frame(width: 16, height: 16)
                Text(UserText.pasteButton)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(baseColor: .blue30))
            )
        }
        .buttonStyle(.plain)
    }
}
