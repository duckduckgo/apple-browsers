//
//  ListBasedPicker.swift
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

/// A generalised view for picking items from a list with checkmark selection.
struct ListBasedPicker<T: Hashable, Footer: View>: View {

    let title: String
    let options: [T]
    @Binding var selectedOption: T
    let descriptionForOption: (T) -> String
    let iconProvider: ((T) -> Image?)?
    let sectionHeader: String?
    let footer: Footer

    init(title: String,
         options: [T],
         selectedOption: Binding<T>,
         descriptionForOption: @escaping (T) -> String,
         iconProvider: ((T) -> Image?)? = nil,
         sectionHeader: String? = nil,
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.options = options
        self._selectedOption = selectedOption
        self.descriptionForOption = descriptionForOption
        self.iconProvider = iconProvider
        self.sectionHeader = sectionHeader
        self.footer = footer()
    }

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.self) { option in
                    Button {
                        selectedOption = option
                    } label: {
                        HStack {
                            iconProvider?(option)

                            Text(verbatim: descriptionForOption(option))
                                .daxBodyRegular()
                                .lineLimit(2)
                                .layoutPriority(1)
                                .foregroundColor(Color(designSystemColor: .textPrimary))

                            Spacer()
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.checkSmall)
                                .foregroundStyle(Color(designSystemColor: .accent))
                                .opacity(selectedOption == option ? 1 : 0)
                        }
                    }
                    .listRowBackground(Color(designSystemColor: .surface))
                }
            } header: {
                if let sectionHeader {
                    Text(sectionHeader)
                }
            } footer: {
                footer
            }
        }
        .navigationTitle(Text(title))
    }
}
