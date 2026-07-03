//
//  SimplifiedScanOrShowCodeView+ViewCodeTab.swift
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
import SwiftUI
import UIComponents

extension SimplifiedScanOrShowCodeView {

    var viewCodeTabContent: some View {
        VStack(spacing: 24) {
            instructionsWithAppChip
                .padding(.top, 24)

            qrCodeContainer

            shareButtons
                .padding(.bottom, Metrics.shareButtonsBottomPadding)
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .overlay(alignment: .bottomLeading) {
            if showCopyConfirmation {
                copyConfirmationCallout
                    .padding(.horizontal, Metrics.copyConfirmationHorizontalPadding)
                    .padding(.bottom, Metrics.shareButtonsBottomPadding + Metrics.copyButtonSize + Metrics.copyConfirmationSpacing)
                    .zIndex(1)
            }
        }
    }

    // MARK: - Instructions With App Chip

    private var instructionsWithAppChip: some View {
        VStack(spacing: 8) {
            Text(UserText.simplifiedViewCodeInstructions)
                .daxSubheadRegular()
                .foregroundColor(SimplifiedSyncStyle.instructionText)
                .multilineTextAlignment(.center)

            appNameChip
        }
        .frame(minHeight: 72)
    }

    private var appNameChip: some View {
        HStack(spacing: 6) {
            Text(UserText.simplifiedViewCodeAppName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)

            Image(uiImage: DesignSystemImages.Color.Size24.appDuckDuckGo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.white)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SimplifiedSyncStyle.screenBackground)
        )
    }

    // MARK: - QR Code Container

    private var qrCodeContainer: some View {
        VStack(spacing: 16) {
            QRCodeView(string: qrCodeModel.qrCodeString, desiredSize: 240, backgroundColor: SimplifiedSyncStyle.qrCodeBackground, flexible: true)
                .padding(.top, 24)

            Text(qrCodeModel.codeForDisplayOrPasting)
                .font(.system(size: 16, design: .monospaced))
                .tracking(2)
                .lineSpacing(8)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .padding(.horizontal, 46)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(SimplifiedSyncStyle.qrCodeBackground)
        )
        .environment(\.colorScheme, .light)
    }

    // MARK: - Share Buttons

    private var shareButtons: some View {
        HStack(spacing: 12) {
            Button {
                model.copyCode()
                showCopyConfirmation = true
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.copy)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(designSystemColor: .controlsFillPrimary))
                    )
            }
            .buttonStyle(.plain)

            Button {
                model.showShareCodeSheet()
            } label: {
                HStack(spacing: 6) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.shareApple)

                    Text(UserText.simplifiedViewCodeShareButton)
                        .daxSubheadSemibold()
                }
                .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SimplifiedSyncStyle.primaryActionBackground)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metrics.copyConfirmationHorizontalPadding)
    }

    private var copyConfirmationCallout: some View {
        BubbleView(
            arrowLength: Metrics.copyConfirmationArrowLength,
            arrowWidth: Metrics.copyConfirmationArrowWidth,
            arrowEdge: .bottom,
            arrowOffset: 0,
            cornerRadius: Metrics.copyConfirmationCornerRadius,
            fillColor: Color(designSystemColor: .surface),
            contentPadding: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        ) {
            copyConfirmationContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
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
        static let horizontalPadding: CGFloat = 16
        static let copyButtonSize: CGFloat = 40
        static let shareButtonsBottomPadding: CGFloat = 16
        static let copyConfirmationSpacing: CGFloat = 8
        static let copyConfirmationArrowLength: CGFloat = 10
        static let copyConfirmationArrowWidth: CGFloat = 14
        static let copyConfirmationCornerRadius: CGFloat = 27
        static let copyConfirmationHorizontalPadding: CGFloat = 12
    }
}
