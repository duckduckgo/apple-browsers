//
//  DataImportHubView.swift
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

struct DataImportHubView: View {

    @ObservedObject var viewModel: DataImportHubViewModel

    var body: some View {
        List {
            Section {
                actionRow(icon: DesignSystemImages.Color.Size24.key,
                          title: UserText.dataImportHubImportPasswordsButton,
                          disclosure: .chevron,
                          action: .importPasswords)

                actionRow(icon: DesignSystemImages.Color.Size24.bookmark,
                          title: UserText.dataImportHubImportBookmarksFromSafariButton,
                          disclosure: .externalLink,
                          action: .importBookmarksFromSafari)
            } header: {
                headerView
            }

            Section(header: Text(UserText.dataImportHubOtherSectionTitle)) {
                actionRow(icon: DesignSystemImages.Glyphs.Size24.uploadFile,
                          title: UserText.dataImportHubUploadExportedFileButton,
                          disclosure: .chevron,
                          action: .uploadExportedFile)
            }
        }
        .applyInsetGroupedListStyle()
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            Image(uiImage: DesignSystemImages.Color.Size128.bringStuff)
                .padding(.bottom, 8)

            Text(UserText.dataImportHubTitle)
                .daxTitle2()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private enum DisclosureStyle {
        case chevron
        case externalLink
    }

    private func actionRow(icon: UIImage,
                           title: String,
                           disclosure: DisclosureStyle,
                           action: DataImportHubViewModel.Action) -> some View {
        Button {
            viewModel.select(action)
        } label: {
            HStack(spacing: 0) {
                Image(uiImage: icon)
                    .padding(.trailing, 8)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(title)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Spacer()
                switch disclosure {
                case .chevron:
                    SettingsCellComponents.chevron
                case .externalLink:
                    SettingsCellComponents.link
                }
            }
        }
    }

}
