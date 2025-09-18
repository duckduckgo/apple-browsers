//
//  SearchWidgetView.swift
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
import WidgetKit
import DesignResourcesKit
import DesignResourcesKitIcons

struct SearchWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        DesignSystemWidgetContainerView {
            VStack(alignment: .center) {

                Image(.logo)
                    .resizable()
                    .useFullColorRendering()
                    .frame(width: 64, height: 64, alignment: .center)
                    .accessibilityHidden(true)

                Spacer()

                ZStack(alignment: Alignment(horizontal: .trailing, vertical: .center)) {

                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(designSystemColor: .backgroundTertiary))
                        .frame(width: 126, height: 46)
                        .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 12, x: 0, y: 8)

                    HStack {
                        Text(UserText.quickActionsSearch)
                            .daxBodyRegular()
                            .foregroundStyle(Color(designSystemColor: .textSecondary))

                        Spacer()

                        Image(uiImage: DesignSystemImages.Glyphs.Size20.findSearch)
                            .useFullColorRendering()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                            .foregroundStyle(Color(designSystemColor: .icons))
                    }
                    .padding(.horizontal, 12)

                }
                .accessibilityHidden(true)
            }.accessibilityLabel(Text(UserText.searchDuckDuckGo))
        }
    }
}
