//
//  ResponsiveSearchFieldView.swift
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

struct ResponsiveSearchFieldView: View {

    @Environment(\.widgetFamily) var widgetFamily

    let isAIChatEnabled: Bool
    let showLogo: Bool
    let isRightIconEnabled: Bool

    var fieldHeight: CGFloat {
        widgetFamily == .systemSmall ? 52 : 46
    }

    var prompt: String {
        widgetFamily == .systemSmall ? UserText.quickActionsSearch : UserText.searchDuckDuckGo
    }

    var body: some View {
        Link(destination: DeepLinks.newSearch) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(designSystemColor: .backgroundTertiary))
                    .frame(minHeight: fieldHeight, maxHeight: fieldHeight)
                    .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 12, x: 0, y: 8)

                HStack(spacing: 0) {

                    if showLogo {
                        Image(uiImage: DesignSystemImages.Color.Size24.duckDuckGo)
                            .resizable()
                            .useFullColorRendering()
                            .frame(width: 30, height: 30, alignment: .leading)
                            .padding(.leading, 12)
                    }

                    Text(prompt)
                        .daxBodyRegular()
                        .makeAccentable()
                        .foregroundStyle(Color(designSystemColor: .textSecondary))
                        .padding(.leading, 8)

                    Spacer()

                    Group {
                        if isRightIconEnabled {
                            if isAIChatEnabled && widgetFamily != .systemSmall {
                                Link(destination: DeepLinks.openAIChat.appendingParameter(name: WidgetSourceType.sourceKey, value: WidgetSourceType.favorite.rawValue)) {
                                    Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat)
                                        .resizable()
                                        .useFullColorRendering()
                                        .frame(width: 24, height: 24, alignment: .leading)
                                        .foregroundStyle(Color(designSystemColor: .icons))
                                }
                            } else  {
                                Image(.widgetSearchLoupe)
                                    .resizable()
                                    .useFullColorRendering()
                                    .frame(width: 24, height: 24, alignment: .leading)
                                    .foregroundStyle(Color(designSystemColor: .icons))
                            }
                        } else {
                            EmptyView()
                        }
                    }
                    .padding(.trailing, 12)

                }

            }
            .padding(.bottom, 16)
            .unredacted()
        }
    }

}
