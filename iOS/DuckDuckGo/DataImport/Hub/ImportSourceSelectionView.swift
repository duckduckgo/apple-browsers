//
//  ImportSourceSelectionView.swift
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

struct ImportSourceSelectionView: View {

    @ObservedObject var viewModel: ImportSourceSelectionViewModel

    var body: some View {
        List {
            ForEach(viewModel.sections, id: \.self) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.sources) { source in
                        sourceRow(source)
                    }
                }
            }
        }
        .applyInsetGroupedListStyle()
    }

    private func sourceRow(_ source: ImportPasswordSource) -> some View {
        Button {
            viewModel.select(source)
        } label: {
            HStack(spacing: 8) {
                source.listIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                Text(source.title)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Spacer()

                SettingsCellComponents.chevron
            }
        }
    }
}
