//
//  LargeSearchFieldView.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct LargeSearchFieldView: View {

    var body: some View {
        Link(destination: DeepLinks.newSearch) {
            ZStack {
                RoundedRectangle(cornerRadius: 23)
                    .fill(Color(designSystemColor: .container))
                    .frame(minHeight: 46, maxHeight: 46)
                    .padding(.vertical, 16)

                HStack {
                    Image(uiImage: DesignSystemImages.Color.Size24.duckDuckGo)
                        .resizable()
                        .useFullColorRendering()
                        .frame(width: 28, height: 28, alignment: .leading)
                        .padding(.leading, 12)

                    Text(UserText.searchDuckDuckGo)
                        .daxBodyRegular()
                        .makeAccentable()

                    Spacer()

                }

            }.unredacted()
        }
    }

}
