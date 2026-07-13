//
//  EnterCodeTabView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import SwiftUI

struct EnterCodeTabView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel

    var body: some View {
        VStack(spacing: 24) {
            instructions
            codeCard
        }
        .padding(.horizontal, 16)
        .onAppear {
            model.delegate?.codeEntryScreenShown()
        }
        .background(Color(designSystemColor: .surfaceSecondary))
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .ignoresSafeArea(.all, edges: .bottom)
    }

    private var instructions: some View {
        VStack(spacing: 16) {
            Text(UserText.simplifiedEnterCodeTitle)
                .daxTitle2()
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(UserText.simplifiedEnterCodeOpenInstruction)
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))

                    SyncAppNameChip()
                }

                SyncInstructionText(markdown: UserText.simplifiedEnterCodeStepsInstruction)
            }
        }
        .padding(.top, 24)
    }

    private var codeCard: some View {
        VStack(spacing: 32) {
            codeArea
            actionArea
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(SimplifiedSyncStyle.subduedPanelBackground)
        )
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var codeArea: some View {
        if let code = model.manuallyEnteredCode {
            Text(code)
                .font(.system(size: 17, design: .monospaced))
                .tracking(2)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 4) {
                Text(UserText.simplifiedEnterCodeExampleLabel)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))

                Text(Constants.exampleCode)
                    .font(.system(size: 17, design: .monospaced))
                    .foregroundColor(Color(designSystemColor: .textTertiary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .opacity(0.5)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if model.isValidating {
            verifyingView
        } else {
            pasteButton
        }
    }

    private var verifyingView: some View {
        HStack {
            ProgressView()
            Text(UserText.simplifiedPasteCodeVerifying)
        }
    }

    private var pasteButton: some View {
        Button {
            model.pasteCode()
        } label: {
            HStack(spacing: 8) {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.paste)
                Text(UserText.simplifiedEnterCodePasteButton)
            }
        }
        .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: false))
    }

    private enum Constants {
        static let exampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ1QjUtNUU2RS00MzQ3LTlDNDQtQjZGQkU4MEZDNEE3In19"
    }
}

#if DEBUG
#Preview {
    let sampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ1QjUtNUU2RS00MzQ3LTlDNDQtQjZGQkU4MEZDNEE3IiwicHJpbWFyeV9rZXkiOiJBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWiJ9fQ=="

    return RebrandedPreview(isRebranded: true) {
        EnterCodeTabView(
            model: ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect)
        )
        .background(SimplifiedSyncStyle.screenBackground)
        .environment(\.colorScheme, .dark)
    }
}

#Preview("Verifying") {
    let sampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ1QjUtNUU2RS00MzQ3LTlDNDQtQjZGQkU4MEZDNEE3IiwicHJpbWFyeV9rZXkiOiJBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWiJ9fQ=="
    let model = ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect)
    model.manuallyEnteredCode = sampleCode
    model.isValidating = true

    return RebrandedPreview(isRebranded: true) {
        EnterCodeTabView(model: model)
            .background(SimplifiedSyncStyle.screenBackground)
            .environment(\.colorScheme, .dark)
    }
}
#endif
