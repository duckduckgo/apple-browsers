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
import MetricBuilder

struct ImportSourceDetailView: View {

    let source: ImportPasswordSource
    var onPrimaryAction: (() -> Void)?
    var onUploadFile: (() -> Void)?

    var body: some View {
        if #available(iOS 17.0, *) {
            detailList
                .contentMargins(.top, 8)
        } else {
            detailList
        }
    }

    private var detailList: some View {
        List {
            Section {
                card
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color(designSystemColor: .surface))

            if let bottomSection = source.bottomSection {
                Section {
                    bottomSectionView(bottomSection)
                } header: {
                    Text(UserText.importDetailDoneExportingHeader)
                }
                .listRowBackground(Color(designSystemColor: .surface))
            }
        }
        .applyInsetGroupedListStyle()
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
                .padding(.horizontal, ButtonStackMetrics.containerPadding)
                .padding(.top, 12)

            if !source.steps.isEmpty {
                stepsView
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            }

            if let buttonTitle = source.primaryButtonTitle {
                primaryButton(title: buttonTitle)
                    .padding(.top, 24)
                    .padding([.horizontal, .bottom], ButtonStackMetrics.containerPadding)
            }
        }
        .frame(maxWidth: .infinity)
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
        let stepText = (try? AttributedString(markdown: markdown)).map(Text.init) ?? Text(markdown)

        return HStack(alignment: .center, spacing: 12) {
            NumberBadge(number: number)
            stepText
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .padding(.vertical, 4)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .padding(.vertical, 4)
    }

    private func primaryButton(title: String) -> some View {
        Button {
            onPrimaryAction?()
        } label: {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bottomSectionView(_ section: ImportPasswordSource.BottomSection) -> some View {
        switch section {
        case .uploadFile:
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
            }
        }
    }
}

#Preview {
    ImportSourceDetailView(source: .safari, onPrimaryAction: {}, onUploadFile: {})
}
