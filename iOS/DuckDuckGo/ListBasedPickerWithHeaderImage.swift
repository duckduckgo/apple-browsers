//
//  ListBasedPickerWithHeaderImage.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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


import Core
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

/// A generalised view for picking items from a list with a static header image.
struct ListBasedPickerWithHeaderImage<T: Hashable>: View {

    let title: String
    let headerImage: Image
    let options: [T]
    let defaultOption: T
    @Binding var selectedOption: T
    let descriptionForOption: (T) -> String
    let iconProvider: ((T) -> Image?)?

    init(title: String,
         headerImage: Image,
         options: [T],
         defaultOption: T,
         selectedOption: Binding<T>,
         descriptionForOption: @escaping (T) -> String,
         iconProvider: ((T) -> Image?)?) {
        self.title = title
        self.headerImage = headerImage
        self.options = options
        self.defaultOption = defaultOption
        self._selectedOption = selectedOption
        self.iconProvider = iconProvider
        self.descriptionForOption = descriptionForOption
    }

    var body: some View {
        List(selection: Binding<T?>(get: {
            nil
        }, set: {
            selectedOption = $0 ?? options[0]
        })) {
            Section {
                HStack {
                    Spacer()
                    headerImage
                    Spacer()
                }
                .listRowBackground(Color(designSystemColor: .surface))

                ForEach(options, id: \.self) { option in
                    HStack {
                        iconProvider?(option)

                        Text(verbatim: descriptionForOption(option))
                            .lineLimit(2)
                            .layoutPriority(1)

                        if selectedOption == option {
                            Spacer()
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.checkSmall)
                                .foregroundStyle(Color(designSystemColor: .accent))
                        } else {
                            Spacer(minLength: 24)
                        }
                    }
                    .listRowBackground(Color(designSystemColor: .surface))
                }
                .navigationTitle(Text(title))
            }
        }
    }

}
