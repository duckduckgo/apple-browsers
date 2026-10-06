//
//  SyncAppNameChip.swift
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

struct SyncAppNameChip: View {

    var name: String = UserText.simplifiedViewCodeAppName

    var body: some View {
        HStack(spacing: 6) {
            Image(uiImage: DesignSystemImages.Color.Size24.appDuckDuckGo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)

            Text(name)
                .daxSubheadSemibold()
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .padding(4)
    }
}

#Preview {
    SyncAppNameChip()
}
