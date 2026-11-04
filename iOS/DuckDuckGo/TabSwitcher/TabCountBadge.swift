//
//  TabCountBadge.swift
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
import DesignResourcesKitIcons

@MainActor
final class TabCountModel: ObservableObject {
    @Published var count: Int

    init(count: Int = 0) {
        self.count = count
    }
}

struct TabCountBadge: View {
    @ObservedObject var model: TabCountModel

    private enum Metrics {
        static let iconSize: CGFloat = 24
        static let maxTextTabs = 100
        
        static let fontSize = 12.0
        static let fontWeight = Font.Weight.bold

        static let symbolFontSize = 14.0
        static let symbolFontWeight = Font.Weight.semibold
        
        static let symbolYOffset: CGFloat = 1
        static let normalYOffset: CGFloat = 0
    }

    var body: some View {
        ZStack {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.tabMobile)
                .renderingMode(.template)

            if model.count > 0 {
                let isShowingSymbol = model.count >= Metrics.maxTextTabs
                let text = isShowingSymbol ? "∞" : "\(model.count)"
                Text(text)
                    .font(textFont(isShowingSymbol))
                    .offset(y: -(isShowingSymbol ? Metrics.symbolYOffset : Metrics.normalYOffset))
            }
        }
        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UserText.numberOfTabs(model.count))
    }
    
    private func textFont(_ isShowingSymbol: Bool) -> Font {
        let size = isShowingSymbol ? Metrics.symbolFontSize : Metrics.fontSize
        let weight = isShowingSymbol ? Metrics.symbolFontWeight : Metrics.fontWeight

        let font = Font.system(size: size, weight: weight)
        if #available(iOS 16.0, *) {
            return font.width(.condensed)
        }
        return font
    }
}
