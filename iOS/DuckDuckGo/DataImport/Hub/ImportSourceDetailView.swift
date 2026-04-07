//
//  ImportSourceDetailView.swift
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

struct ImportSourceDetailView: View {

    let source: ImportPasswordSource
    var onPrimaryAction: (() -> Void)?
    var onUploadFile: (() -> Void)?
    var onGetDesktopBrowser: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                card
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if let bottomSection = source.bottomSection {
                    bottomSectionView(bottomSection)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(designSystemColor: .background))
    }

    private var card: some View {
        VStack(spacing: 0) {
            source.detailIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .padding(.top, 24)

            Text(source.detailDescription)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if !source.steps.isEmpty {
                stepsView
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            }

            if let buttonTitle = source.primaryButtonTitle {
                primaryButton(title: buttonTitle)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(designSystemColor: .surface))
        )
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(source.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Divider()
                        .padding(.leading, 52)
                }
                stepRow(number: index + 1, markdown: step)
            }
        }
        .padding(.horizontal, 16)
    }

    private func stepRow(number: Int, markdown: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NumberBadge(number: number)

            if let attributed = try? AttributedString(markdown: markdown) {
                Text(attributed)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            } else {
                Text(markdown)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func primaryButton(title: String) -> some View {
        Button {
            onPrimaryAction?()
        } label: {
            HStack(spacing: 8) {
                if source.primaryButtonHasQRIcon {
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.qr)
                }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bottomSectionView(_ section: ImportPasswordSource.BottomSection) -> some View {
        switch section {
        case .uploadFile:
            VStack(alignment: .leading, spacing: 8) {
                Text(UserText.importDetailDoneExportingHeader)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .textCase(.uppercase)
                    .padding(.leading, 4)

                Button {
                    onUploadFile?()
                } label: {
                    HStack(spacing: 8) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.uploadFile)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        Text(UserText.importDetailUploadFileRow)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        Spacer()
                        SettingsCellComponents.chevron
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(designSystemColor: .surface))
                )
            }

        case .getDesktopBrowser:
            Button {
                onGetDesktopBrowser?()
            } label: {
                HStack(spacing: 8) {
                    Image(uiImage: DesignSystemImages.Color.Size24.deviceLaptopInstall)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UserText.importDetailGetDesktopBrowserTitle)
                            .daxBodyRegular()
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        Text(UserText.importDetailGetDesktopBrowserSubtitle)
                            .daxFootnoteRegular()
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                    Spacer()
                    SettingsCellComponents.chevron
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(designSystemColor: .surface))
            )
        }
    }
}
