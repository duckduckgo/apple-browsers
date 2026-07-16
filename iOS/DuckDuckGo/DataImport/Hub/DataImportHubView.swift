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
            ForEach(viewModel.sections, id: \.self) { section in
                Section {
                    ForEach(section.sources) { source in
                        sourceRow(source)
                    }
                } header: {
                    sectionHeader(for: section)
                }
                .listRowBackground(Color(designSystemColor: .surface))
            }
        }
        .applyInsetGroupedListStyle()
    }

    private var hubHeaderView: some View {
        VStack(spacing: 0) {
            Group {
                if AppRebrand.isAppRebranded() {
                    Image(uiImage: DesignSystemImages.Color.Size128.bringStuffDownload)
                } else {
                    Image(uiImage: DesignSystemImages.Color.Size128.bringStuff)
                }
            }
            .padding(.bottom, 8)

            Text(UserText.dataImportHubTitle)
                .daxTitle2()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func sectionHeader(for section: ImportPasswordSource.Section) -> some View {
        if section == .importFrom {
            VStack(spacing: 0) {
                hubHeaderView
                Text(section.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(section.title)
        }
    }

    private func sourceRow(_ source: ImportPasswordSource) -> some View {
        Button {
            viewModel.select(source)
        } label: {
            HStack(spacing: 0) {
                source.listIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .padding(.trailing, 8)
                Text(source.title)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Spacer()
                SettingsCellComponents.chevron
            }
        }
    }

}

#Preview {
    DataImportHubView(viewModel: DataImportHubViewModel())
}
