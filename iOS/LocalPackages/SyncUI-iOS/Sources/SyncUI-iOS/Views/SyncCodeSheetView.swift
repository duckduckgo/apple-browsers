//
//  SyncCodeSheetView.swift
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
import UIComponents

struct SyncCodeSheetView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCopyConfirmation = false

    var body: some View {
        NavigationView {
            VStack(spacing: Metrics.contentSpacing) {
                instructions
                qrCard
                shareButton
            }
            .padding(Metrics.contentPadding)
            .background(SimplifiedSyncStyle.screenBackground)
            .navigationTitle(UserText.simplifiedSyncCodeSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopyConfirmation {
                    copyConfirmationCallout
                        .offset(y: copyConfirmationOffset)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var instructions: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(UserText.simplifiedSyncCodeSheetOpenInstruction)
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))

                    SyncAppNameChip()
                }

                SyncInstructionText(markdown: UserText.simplifiedSyncCodeSheetScanInstruction)
            }
        }
    }

    private var qrCard: some View {
        VStack(spacing: 16) {
            QRCodeView(string: model.showQRCodeModel.qrCodeString, desiredSize: 320, backgroundColor: SimplifiedSyncStyle.qrCodeBackground, flexible: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(model.showQRCodeModel.codeForDisplayOrPasting)
                .font(.system(size: 16, design: .monospaced))
                .tracking(2)
                .lineSpacing(8)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.copyCode()
                showCopyConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.copy)
                    Text(UserText.simplifiedSyncCodeCopyButton)
                }
            }
            .buttonStyle(SecondaryFillButtonStyle(compact: true))
        }
        .padding(Metrics.contentPadding)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(SimplifiedSyncStyle.qrCodeBackground)
        )
        .environment(\.colorScheme, .light)
    }

    private var shareButton: some View {
        Button {
            model.showShareCodeSheet()
        } label: {
            HStack(spacing: 8) {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.shareApple)
                Text(UserText.simplifiedViewCodeShareButton)
            }
        }
        .buttonStyle(SecondaryFillButtonStyle(compact: true))
    }

    private var copyConfirmationOffset: CGFloat {
        -(Metrics.contentPadding
          + Metrics.buttonHeight
          + Metrics.contentSpacing
          + Metrics.contentPadding
          + Metrics.buttonHeight
          + Metrics.copyConfirmationSpacing)
    }

    private var copyConfirmationCallout: some View {
        BubbleView(
            arrowLength: Metrics.copyConfirmationArrowLength,
            arrowWidth: Metrics.copyConfirmationArrowWidth,
            arrowEdge: .bottom,
            arrowOffset: 0.4,
            cornerRadius: Metrics.copyConfirmationCornerRadius,
            fillColor: Color(designSystemColor: .surface),
            contentPadding: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        ) {
            copyConfirmationContent
        }
        .padding(.horizontal)
        .environment(\.colorScheme, .light)
    }

    private var copyConfirmationContent: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(UserText.simplifiedViewCodeCopyConfirmationTitle)
                    .daxSubheadSemibold()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(UserText.simplifiedViewCodeCopyConfirmationMessage)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                showCopyConfirmation = false
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.close)
            }
            .buttonStyle(CloseButtonStyle())
        }
    }

    private enum Metrics {
        static let contentPadding: CGFloat = 24
        static let contentSpacing: CGFloat = 24
        static let buttonHeight: CGFloat = 40
        static let copyConfirmationSpacing: CGFloat = 8
        static let copyConfirmationArrowLength: CGFloat = 10
        static let copyConfirmationArrowWidth: CGFloat = 14
        static let copyConfirmationCornerRadius: CGFloat = 27
    }
}

#if DEBUG
#Preview {
    let sampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ1QjUtNUU2RS00MzQ3LTlDNDQtQjZGQkU4MEZDNEE3IiwicHJpbWFyeV9rZXkiOiJBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWiJ9fQ=="

    return RebrandedPreview(isRebranded: true) {
        SyncCodeSheetView(
            model: ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect)
        )
    }
}
#endif
