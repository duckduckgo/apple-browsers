//
//  NewImportErrorView.swift
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
import DesignResourcesKitIcons
import DesignResourcesKit

struct NewImportErrorView: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size24.info).frame(width: 24, height: 24)
            Text(text)
        }
        .background(Color(designSystemColor: .surfaceSecondary))
        .cornerRadius(10)
        .overlay(
        RoundedRectangle(cornerRadius: 10)
            .inset(by: 0.5).stroke()
        )
    }
}
