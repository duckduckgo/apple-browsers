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
        widgetFamily == .systemSmall && showLogo ? 52 : 46
    }

    var prompt: String {
        widgetFamily == .systemSmall ? UserText.quickActionsSearch : UserText.searchDuckDuckGo
    }

    var body: some View {
        Link(destination: DeepLinks.newSearch) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .renderAwareBackgroundFill()
                    .frame(minHeight: fieldHeight, maxHeight: fieldHeight)
                    .shadow(color: Color(designSystemColor: .shadowSecondary), radius: 12, x: 0, y: 8)
                    .makeAccentable()

                HStack(spacing: 0) {

                    if showLogo {
                        ResizableTintableImage(fullColor: UIImage(resource: .widgetDaxLogo),
                                      tintable: UIImage(resource: .widgetDaxLogoTinted))
                                      .frame(width: 24, height: 24, alignment: .leading)
                                      .padding(.leading, 12)
                    }

                    Text(prompt)
                        .daxBodyRegular()
                        .foregroundStyle(Color(designSystemColor: .textSecondary))
                        .padding(.leading, showLogo ? 8 : 12)
                        .makeAccentable()

                    Spacer()

                    Group {
                        if isRightIconEnabled {
                            if isAIChatEnabled && widgetFamily != .systemSmall {
                                Link(destination: DeepLinks.openAIChat.appendingParameter(name: WidgetSourceType.sourceKey, value: WidgetSourceType.favorite.rawValue)) {
                                    Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat)
                                        .resizable()
                                        .makeAccentable()
                                        .frame(width: 24, height: 24, alignment: .leading)
                                        .foregroundStyle(Color(designSystemColor: .icons))
                                }
                            } else  {
                                Image(.widgetSearchLoupe)
                                    .resizable()
                                    .makeAccentable()
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
            .unredacted()
        }
    }

}
